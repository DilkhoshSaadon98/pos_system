/// Schema version 3 — the shift, the second currency, and what the labels say.
///
/// Three things a shop needs before the software can be trusted with money:
///
/// * **A shift.** Cash is only auditable between two counts. A shift opens with
///   a float, every cash movement made during it is tagged with its id, and it
///   closes with a physical count. The difference between what the drawer holds
///   and what the ledger says it should hold is posted — not hidden — to its
///   own account, so a till that is short by 2,000 on Tuesday leaves a trace.
///
/// * **A second currency.** In this trade the price list is in dinars and half
///   the customers pay in dollars. A tender therefore records what was actually
///   handed over (`amount_fx_minor`, in the foreign currency's own minor
///   units), the rate it was taken at, and the base-currency value that went
///   into the books. The rate lives on the tender, never only in settings: a
///   receipt reprinted next month must show the rate that was used that day.
///
/// * **Labels.** What a printed shelf label carries, so the choice survives a
///   restart and a reinstall.
///
/// ## The one convention worth remembering
///
/// Every amount in this app, in either currency, is stored as **hundredths** —
/// the scale `Money` uses. How many decimals a currency is written with is a
/// display choice and never changes what is stored. Because both sides sit at
/// the same scale, `fx_rate_milli` is just the human rate times 1000:
///
/// ```
///   1 USD = 1,320 IQD          → fx_rate_milli = 1,320,000
///   $10 taken                  → amount_fx_minor = 1,000
///   amount_minor = mulDivRound(1000, 1320000, 1000) = 1,320,000  (13,200 IQD)
/// ```
///
/// One multiply, one rounding, and no floating point anywhere near the drawer.
///
/// Everything here is additive: v1 and v2 columns keep their meaning, so an
/// existing shop upgrades by running these statements and nothing else.
library;

const List<String> schemaV3 = <String>[
  // ------------------------------------------------------------- shifts ---
  '''
CREATE TABLE cash_shifts (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  shift_no            TEXT    NOT NULL,
  user_id             INTEGER REFERENCES users(id) ON DELETE SET NULL,
  opened_at           TEXT    NOT NULL,

  -- The money put in the drawer before the first sale, counted in both
  -- currencies. The foreign float is in that currency's own minor units.
  opening_float_minor    INTEGER NOT NULL DEFAULT 0 CHECK (opening_float_minor >= 0),
  opening_float_fx_minor INTEGER NOT NULL DEFAULT 0 CHECK (opening_float_fx_minor >= 0),

  closed_at           TEXT,
  closed_by_user_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,

  -- What was counted by hand at the close, in each currency.
  counted_minor       INTEGER,
  counted_fx_minor    INTEGER,

  -- The rate the foreign cash was valued at when the shift was closed.
  fx_rate_milli       INTEGER NOT NULL DEFAULT 0 CHECK (fx_rate_milli >= 0),

  -- What the ledger says the drawer should hold, and counted − expected.
  -- A negative difference is a shortage.
  expected_minor      INTEGER,
  expected_fx_minor   INTEGER,
  difference_minor    INTEGER,

  journal_entry_id    INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL,
  note                TEXT,
  status              TEXT    NOT NULL DEFAULT 'open'
                              CHECK (status IN ('open','closed')),
  created_at          TEXT    NOT NULL,
  updated_at          TEXT    NOT NULL,

  -- A shift that is closed has been counted; one that is open has not.
  CHECK ((status = 'open'  AND closed_at IS NULL AND counted_minor IS NULL)
      OR (status = 'closed' AND closed_at IS NOT NULL AND counted_minor IS NOT NULL))
)''',

  // One cashier, one open drawer. The partial index is what makes a second
  // "open shift" impossible rather than merely discouraged.
  '''CREATE UNIQUE INDEX ux_shift_one_open_per_user
       ON cash_shifts(user_id) WHERE status = 'open' ''',
  'CREATE INDEX ix_shift_opened ON cash_shifts(opened_at)',
  "CREATE UNIQUE INDEX ux_shift_no ON cash_shifts(shift_no)",

  // Which shift a document belongs to. Nullable, because a shop that turns the
  // requirement off still posts documents, and because every row that existed
  // before this migration belongs to no shift at all.
  'ALTER TABLE sales_invoices ADD COLUMN shift_id INTEGER REFERENCES cash_shifts(id) ON DELETE SET NULL',
  'ALTER TABLE purchase_invoices ADD COLUMN shift_id INTEGER REFERENCES cash_shifts(id) ON DELETE SET NULL',
  'ALTER TABLE payments ADD COLUMN shift_id INTEGER REFERENCES cash_shifts(id) ON DELETE SET NULL',

  // The shift tag that actually decides the count. Sales are not the only way
  // money reaches the drawer — a supplier paid in cash, a customer settling an
  // old invoice, an owner's draw — so the tag belongs on the journal entry,
  // which is the one thing every movement passes through.
  'ALTER TABLE journal_entries ADD COLUMN shift_id INTEGER REFERENCES cash_shifts(id) ON DELETE SET NULL',
  'CREATE INDEX ix_journal_shift ON journal_entries(shift_id)',
  'CREATE INDEX ix_sales_shift ON sales_invoices(shift_id)',

  // ---------------------------------------------------- second currency ---
  // What the customer actually handed over. `amount_minor` keeps its meaning:
  // the value in the shop's own currency, which is what the journal posts.
  "ALTER TABLE sale_tenders ADD COLUMN currency_code TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE sale_tenders ADD COLUMN fx_rate_milli INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE sale_tenders ADD COLUMN amount_fx_minor INTEGER NOT NULL DEFAULT 0',

  // The same three on a receipt or a supplier payment.
  "ALTER TABLE payments ADD COLUMN currency_code TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE payments ADD COLUMN fx_rate_milli INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE payments ADD COLUMN amount_fx_minor INTEGER NOT NULL DEFAULT 0',

  // A tender in a foreign currency must carry its rate, and one in the shop's
  // own currency must not pretend to. Enforced here because the alternative is
  // trusting every screen that will ever post a tender.
  '''
CREATE TRIGGER trg_tender_fx_rate_required
BEFORE INSERT ON sale_tenders
FOR EACH ROW
WHEN NEW.currency_code <> '' AND (NEW.fx_rate_milli <= 0 OR NEW.amount_fx_minor = 0)
BEGIN
  SELECT RAISE(ABORT, 'a tender in another currency needs a rate and an amount');
END''',

  // ---------------------------------------------------------- audit log ---
  'ALTER TABLE audit_log ADD COLUMN shift_id INTEGER REFERENCES cash_shifts(id) ON DELETE SET NULL',
  'CREATE INDEX ix_audit_entity ON audit_log(entity, entity_id)',
  'CREATE INDEX ix_audit_user ON audit_log(user_id)',

  // ------------------------------------------------------------- views ----
  // Everything a shift report needs, in one row per shift.
  //
  // The cash movement deliberately excludes the shift's own closing entry:
  // that entry exists to *record* the difference, and counting it would make
  // the expected figure chase the counted one. It is excluded by id rather
  // than by source type, so a period-closing entry made during the shift still
  // counts if it moved cash.
  '''
CREATE VIEW v_shift_totals AS
SELECT
  s.id                  AS shift_id,
  s.shift_no,
  s.user_id,
  u.full_name           AS user_name,
  s.opened_at,
  s.closed_at,
  s.status,
  s.opening_float_minor,
  s.opening_float_fx_minor,
  s.counted_minor,
  s.counted_fx_minor,
  s.expected_minor      AS recorded_expected_minor,
  s.difference_minor,

  IFNULL((SELECT SUM(l.debit_minor - l.credit_minor)
            FROM journal_lines l
            JOIN accounts a         ON a.id = l.account_id
            JOIN journal_entries e  ON e.id = l.entry_id
           WHERE e.shift_id = s.id
             AND e.is_void = 0
             AND (s.journal_entry_id IS NULL OR e.id <> s.journal_entry_id)
             AND a.system_key = 'cash'), 0)     AS cash_movement_minor,

  IFNULL((SELECT SUM(l.debit_minor - l.credit_minor)
            FROM journal_lines l
            JOIN accounts a         ON a.id = l.account_id
            JOIN journal_entries e  ON e.id = l.entry_id
           WHERE e.shift_id = s.id
             AND e.is_void = 0
             AND (s.journal_entry_id IS NULL OR e.id <> s.journal_entry_id)
             AND a.system_key = 'cash_usd'), 0) AS cash_fx_movement_minor,

  (SELECT COUNT(*) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.doc_type = 'sale'
      AND i.status <> 'void')                   AS sales_count,
  IFNULL((SELECT SUM(i.total_minor) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.doc_type = 'sale'
      AND i.status <> 'void'), 0)               AS sales_total_minor,
  IFNULL((SELECT SUM(i.profit_minor) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.doc_type = 'sale'
      AND i.status <> 'void'), 0)               AS sales_profit_minor,
  (SELECT COUNT(*) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.doc_type = 'sale_return'
      AND i.status <> 'void')                   AS returns_count,
  IFNULL((SELECT SUM(i.total_minor) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.doc_type = 'sale_return'
      AND i.status <> 'void'), 0)               AS returns_total_minor,
  (SELECT COUNT(*) FROM sales_invoices i
    WHERE i.shift_id = s.id AND i.status = 'void')  AS voids_count
FROM cash_shifts s
LEFT JOIN users u ON u.id = s.user_id''',

  // What was taken, split by method and currency — the body of the Z report.
  '''
CREATE VIEW v_shift_tenders AS
SELECT
  i.shift_id,
  t.method,
  t.direction,
  CASE WHEN t.currency_code = '' THEN NULL ELSE t.currency_code END AS currency_code,
  COUNT(*)                                    AS tender_count,
  IFNULL(SUM(CASE WHEN t.direction = 'in'  THEN t.amount_minor
                  ELSE -t.amount_minor END), 0)    AS amount_minor,
  IFNULL(SUM(CASE WHEN t.direction = 'in'  THEN t.amount_fx_minor
                  ELSE -t.amount_fx_minor END), 0) AS amount_fx_minor
FROM sale_tenders t
JOIN sales_invoices i ON i.id = t.invoice_id AND i.status <> 'void'
WHERE i.shift_id IS NOT NULL
GROUP BY i.shift_id, t.method, t.direction, t.currency_code''',

  // The audit trail with the names filled in, so the screen is one plain query.
  '''
CREATE VIEW v_audit_log AS
SELECT
  a.id, a.happened_at, a.action, a.entity, a.entity_id, a.detail,
  a.user_id, u.full_name AS user_name, u.username,
  a.shift_id, s.shift_no
FROM audit_log a
LEFT JOIN users u       ON u.id = a.user_id
LEFT JOIN cash_shifts s ON s.id = a.shift_id''',
];

/// Settings introduced with schema v3.
///
/// Inserted on a fresh database and back-filled on an upgrade — a missing key
/// reads as an empty string, which would quietly disable the shift requirement
/// or, worse, price a dollar at zero.
const Map<String, String> settingsV3 = <String, String>{
  // ---- shifts ----
  // '1' — a cashier must open a shift before the till will take a sale.
  'shifts_required': '1',
  // Print the Z report automatically when a shift is closed.
  'shift_print_on_close': '1',

  // ---- second currency ----
  'fx_enabled': '1',
  'fx_currency_code': 'USD',
  'fx_currency_symbol': '\$',
  'fx_decimals': '2',
  // How many units of the shop's currency one unit of the foreign currency
  // buys, as typed by a human: 1 USD = 1320 IQD.
  'fx_rate': '1320',
  // Round dinar change to the nearest 250 when a dollar note is taken, because
  // nobody has a 3-dinar note. 0 turns it off.
  'fx_change_rounding': '250',

  // ---- labels ----
  'label_size': '50x30',
  'label_barcode': 'auto',
  'label_show_name': '1',
  'label_show_price': '1',
  'label_show_shop': '0',
  'label_columns': '3',

  'schema_notes': 'v3',
};

/// The accounts v3 needs, as `system_key → (code, English, Arabic, Kurdish,
/// type, normal side, parent code)`.
///
/// Inserted after the seed rather than inside [schemaV3], because on a fresh
/// database the schema runs before there is a chart of accounts to hang them
/// on. Adding one that already exists is a no-op, so this is safe to run on
/// every open.
const Map<String, List<String>> accountsV3 = <String, List<String>>{
  'cash_usd': <String>[
    '1015',
    'Cash box (foreign currency)',
    'الصندوق (عملة أجنبية)',
    'سندوقی دراوی بیانی',
    'asset',
    'debit',
    '1',
  ],
  'cash_over_short': <String>[
    '5095',
    'Cash over and short',
    'زيادة ونقص الصندوق',
    'زیادە و کەمی سندوق',
    'expense',
    'debit',
    '5',
  ],
  'fx_difference': <String>[
    '5090',
    'Exchange differences',
    'فروق العملة',
    'جیاوازی دراو',
    'expense',
    'debit',
    '5',
  ],
};
