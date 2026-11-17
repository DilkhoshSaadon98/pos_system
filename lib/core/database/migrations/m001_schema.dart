/// Schema version 1 of the redesigned cashier database.
///
/// Design rules that the whole app depends on — break one of these and the
/// numbers stop adding up:
///
/// * **Money is never a floating point number.** Every amount is an INTEGER of
///   minor units (1/100 of the currency). `1 500 IQD` is stored as `150000`.
///   Display formatting decides how many decimals the user sees; the storage
///   never changes. Columns holding money end in `_minor`.
/// * **Quantities are integers too**, in thousandths of a unit, so 0.25 kg is
///   `250`. Columns end in `_milli`.
/// * **Percentages are basis points** (`_bp`): 7.5 % is `750`. No 0.075 doubles.
/// * **Stock has exactly one source of truth**: `stock_moves`. `items.stock_qty_milli`
///   is a cache maintained by triggers, never written by application code.
/// * **Accounting is real double entry**: `journal_entries` + `journal_lines`,
///   every entry balanced. No transaction row carries "source/target account"
///   any more, and no view hardcodes an account id — accounts are found by
///   `system_key`.
/// * Every table that the user can edit carries `created_at` / `updated_at`
///   as ISO-8601 strings in local time.
library;

const List<String> schemaV1 = <String>[
  // ---------------------------------------------------------------- meta ---
  '''
CREATE TABLE app_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
  '''
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT,
  updated_at TEXT NOT NULL
)''',
  '''
CREATE TABLE counters (
  name       TEXT PRIMARY KEY,
  prefix     TEXT NOT NULL DEFAULT '',
  period     TEXT NOT NULL DEFAULT '',
  last_value INTEGER NOT NULL DEFAULT 0
)''',

  // --------------------------------------------------------------- users ---
  '''
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  full_name     TEXT NOT NULL,
  username      TEXT NOT NULL COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('owner','manager','cashier','accountant')),
  phone         TEXT,
  is_active     INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  last_login_at TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_users_username ON users(username)',

  // ------------------------------------------------------------ accounts ---
  '''
CREATE TABLE accounts (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL,
  name        TEXT NOT NULL,
  name_ar     TEXT,
  name_ku     TEXT,
  type        TEXT NOT NULL CHECK (type IN ('asset','liability','equity','revenue','expense')),
  normal_side TEXT NOT NULL CHECK (normal_side IN ('debit','credit')),
  parent_id   INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
  system_key  TEXT,
  is_group    INTEGER NOT NULL DEFAULT 0 CHECK (is_group IN (0,1)),
  is_active   INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  note        TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_accounts_code ON accounts(code)',
  "CREATE UNIQUE INDEX ux_accounts_system_key ON accounts(system_key) WHERE system_key IS NOT NULL AND system_key <> ''",
  'CREATE INDEX ix_accounts_parent ON accounts(parent_id)',

  // ------------------------------------------------------------- parties ---
  '''
CREATE TABLE parties (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  code               TEXT,
  name               TEXT NOT NULL,
  kind               TEXT NOT NULL CHECK (kind IN ('customer','supplier','both','employee')),
  phone              TEXT,
  phone2             TEXT,
  email              TEXT,
  address            TEXT,
  note               TEXT,
  account_id         INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
  credit_limit_minor INTEGER NOT NULL DEFAULT 0 CHECK (credit_limit_minor >= 0),
  is_active          INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
)''',
  "CREATE UNIQUE INDEX ux_parties_code ON parties(code) WHERE code IS NOT NULL AND code <> ''",
  'CREATE INDEX ix_parties_kind ON parties(kind, is_active)',
  'CREATE INDEX ix_parties_name ON parties(name)',
  'CREATE INDEX ix_parties_account ON parties(account_id)',

  // ------------------------------------------------------------- journal ---
  '''
CREATE TABLE journal_entries (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_no       TEXT NOT NULL,
  entry_date     TEXT NOT NULL,
  posted_at      TEXT NOT NULL,
  source_type    TEXT NOT NULL CHECK (source_type IN (
                   'sale','sale_return','purchase','purchase_return','receipt','payment',
                   'expense','opening','manual','adjustment','transfer','closing')),
  source_id      INTEGER,
  memo           TEXT,
  user_id        INTEGER REFERENCES users(id) ON DELETE SET NULL,
  is_void        INTEGER NOT NULL DEFAULT 0 CHECK (is_void IN (0,1)),
  reversal_of_id INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL
)''',
  'CREATE UNIQUE INDEX ux_journal_entry_no ON journal_entries(entry_no)',
  'CREATE INDEX ix_journal_date ON journal_entries(entry_date)',
  'CREATE INDEX ix_journal_source ON journal_entries(source_type, source_id)',
  '''
CREATE TABLE journal_lines (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id     INTEGER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  account_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  party_id     INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  debit_minor  INTEGER NOT NULL DEFAULT 0 CHECK (debit_minor  >= 0),
  credit_minor INTEGER NOT NULL DEFAULT 0 CHECK (credit_minor >= 0),
  memo         TEXT,
  line_no      INTEGER NOT NULL DEFAULT 0,
  CHECK (NOT (debit_minor > 0 AND credit_minor > 0))
)''',
  'CREATE INDEX ix_journal_lines_entry ON journal_lines(entry_id)',
  'CREATE INDEX ix_journal_lines_account ON journal_lines(account_id)',
  'CREATE INDEX ix_journal_lines_party ON journal_lines(party_id)',

  // ------------------------------------------------------------- catalog ---
  '''
CREATE TABLE categories (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  name_ar    TEXT,
  name_ku    TEXT,
  parent_id  INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  image_path TEXT,
  color      TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
  'CREATE INDEX ix_categories_parent ON categories(parent_id)',
  '''
CREATE TABLE units (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  name_ar    TEXT,
  name_ku    TEXT,
  symbol     TEXT,
  allow_fraction INTEGER NOT NULL DEFAULT 0 CHECK (allow_fraction IN (0,1)),
  is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_units_name ON units(name)',
  '''
CREATE TABLE items (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  sku                 TEXT,
  name                TEXT NOT NULL,
  name_ar             TEXT,
  name_ku             TEXT,
  category_id         INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  base_unit_id        INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  description         TEXT,
  image_path          TEXT,
  track_stock         INTEGER NOT NULL DEFAULT 1 CHECK (track_stock IN (0,1)),
  is_service          INTEGER NOT NULL DEFAULT 0 CHECK (is_service IN (0,1)),
  allow_negative      INTEGER NOT NULL DEFAULT 0 CHECK (allow_negative IN (0,1)),
  avg_cost_minor      INTEGER NOT NULL DEFAULT 0 CHECK (avg_cost_minor >= 0),
  last_cost_minor     INTEGER NOT NULL DEFAULT 0 CHECK (last_cost_minor >= 0),
  stock_qty_milli     INTEGER NOT NULL DEFAULT 0,
  reorder_level_milli INTEGER NOT NULL DEFAULT 0,
  tax_rate_bp         INTEGER NOT NULL DEFAULT 0 CHECK (tax_rate_bp >= 0),
  production_date     TEXT,
  expiry_date         TEXT,
  is_active           INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL
)''',
  "CREATE UNIQUE INDEX ux_items_sku ON items(sku) WHERE sku IS NOT NULL AND sku <> ''",
  'CREATE INDEX ix_items_category ON items(category_id, is_active)',
  'CREATE INDEX ix_items_name ON items(name)',
  '''
CREATE TABLE item_units (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id               INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  unit_id               INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  factor_milli          INTEGER NOT NULL CHECK (factor_milli > 0),
  sell_price_minor      INTEGER NOT NULL DEFAULT 0 CHECK (sell_price_minor >= 0),
  wholesale_price_minor INTEGER NOT NULL DEFAULT 0 CHECK (wholesale_price_minor >= 0),
  min_price_minor       INTEGER NOT NULL DEFAULT 0 CHECK (min_price_minor >= 0),
  barcode               TEXT,
  is_base               INTEGER NOT NULL DEFAULT 0 CHECK (is_base IN (0,1)),
  is_default_sale       INTEGER NOT NULL DEFAULT 0 CHECK (is_default_sale IN (0,1)),
  is_default_purchase   INTEGER NOT NULL DEFAULT 0 CHECK (is_default_purchase IN (0,1)),
  sort_order            INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE UNIQUE INDEX ux_item_units ON item_units(item_id, unit_id)',
  "CREATE UNIQUE INDEX ux_item_units_barcode ON item_units(barcode) WHERE barcode IS NOT NULL AND barcode <> ''",
  'CREATE INDEX ix_item_units_item ON item_units(item_id)',

  // --------------------------------------------------------------- stock ---
  '''
CREATE TABLE stock_moves (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id             INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  moved_at            TEXT NOT NULL,
  kind                TEXT NOT NULL CHECK (kind IN (
                        'opening','purchase','purchase_return','sale','sale_return',
                        'adjustment','waste','production')),
  qty_milli           INTEGER NOT NULL,
  unit_cost_minor     INTEGER NOT NULL DEFAULT 0,
  cost_total_minor    INTEGER NOT NULL DEFAULT 0,
  balance_after_milli INTEGER NOT NULL DEFAULT 0,
  doc_type            TEXT,
  doc_id              INTEGER,
  doc_line_id         INTEGER,
  user_id             INTEGER REFERENCES users(id) ON DELETE SET NULL,
  note                TEXT
)''',
  'CREATE INDEX ix_stock_moves_item ON stock_moves(item_id, moved_at)',
  'CREATE INDEX ix_stock_moves_doc ON stock_moves(doc_type, doc_id)',
  'CREATE INDEX ix_stock_moves_date ON stock_moves(moved_at)',

  // `items.stock_qty_milli` is a cache. These three triggers are the only
  // thing allowed to write it, so the cache can never drift from the ledger.
  '''
CREATE TRIGGER trg_stock_moves_ai AFTER INSERT ON stock_moves
BEGIN
  UPDATE items SET stock_qty_milli = stock_qty_milli + NEW.qty_milli
   WHERE id = NEW.item_id;
END''',
  '''
CREATE TRIGGER trg_stock_moves_au AFTER UPDATE ON stock_moves
BEGIN
  UPDATE items SET stock_qty_milli = stock_qty_milli - OLD.qty_milli
   WHERE id = OLD.item_id;
  UPDATE items SET stock_qty_milli = stock_qty_milli + NEW.qty_milli
   WHERE id = NEW.item_id;
END''',
  '''
CREATE TRIGGER trg_stock_moves_ad AFTER DELETE ON stock_moves
BEGIN
  UPDATE items SET stock_qty_milli = stock_qty_milli - OLD.qty_milli
   WHERE id = OLD.item_id;
END''',

  // --------------------------------------------------------------- sales ---
  '''
CREATE TABLE sales_invoices (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_no             TEXT NOT NULL,
  doc_type               TEXT NOT NULL DEFAULT 'sale' CHECK (doc_type IN ('sale','sale_return')),
  party_id               INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  issued_at              TEXT NOT NULL,
  user_id                INTEGER REFERENCES users(id) ON DELETE SET NULL,
  price_mode             TEXT NOT NULL DEFAULT 'retail' CHECK (price_mode IN ('retail','wholesale')),
  gross_minor            INTEGER NOT NULL DEFAULT 0,
  line_discount_minor    INTEGER NOT NULL DEFAULT 0,
  invoice_discount_minor INTEGER NOT NULL DEFAULT 0,
  discount_total_minor   INTEGER NOT NULL DEFAULT 0,
  subtotal_minor         INTEGER NOT NULL DEFAULT 0,
  tax_minor              INTEGER NOT NULL DEFAULT 0,
  service_charge_minor   INTEGER NOT NULL DEFAULT 0,
  rounding_minor         INTEGER NOT NULL DEFAULT 0,
  total_minor            INTEGER NOT NULL DEFAULT 0,
  paid_minor             INTEGER NOT NULL DEFAULT 0,
  change_minor           INTEGER NOT NULL DEFAULT 0,
  due_minor              INTEGER NOT NULL DEFAULT 0,
  cost_minor             INTEGER NOT NULL DEFAULT 0,
  profit_minor           INTEGER NOT NULL DEFAULT 0,
  items_count            INTEGER NOT NULL DEFAULT 0,
  status                 TEXT NOT NULL DEFAULT 'posted'
                         CHECK (status IN ('posted','void','returned','partially_returned')),
  return_of_id           INTEGER REFERENCES sales_invoices(id) ON DELETE SET NULL,
  journal_entry_id       INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL,
  note                   TEXT,
  created_at             TEXT NOT NULL,
  updated_at             TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_sales_invoice_no ON sales_invoices(invoice_no)',
  'CREATE INDEX ix_sales_issued ON sales_invoices(issued_at)',
  'CREATE INDEX ix_sales_party ON sales_invoices(party_id)',
  'CREATE INDEX ix_sales_status ON sales_invoices(status, doc_type)',
  '''
CREATE TABLE sales_invoice_lines (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id           INTEGER NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
  item_id              INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  item_unit_id         INTEGER REFERENCES item_units(id) ON DELETE SET NULL,
  unit_name            TEXT NOT NULL DEFAULT '',
  factor_milli         INTEGER NOT NULL DEFAULT 1000,
  qty_milli            INTEGER NOT NULL,
  qty_base_milli       INTEGER NOT NULL,
  unit_price_minor     INTEGER NOT NULL DEFAULT 0,
  gross_minor          INTEGER NOT NULL DEFAULT 0,
  line_discount_minor  INTEGER NOT NULL DEFAULT 0,
  alloc_discount_minor INTEGER NOT NULL DEFAULT 0,
  net_minor            INTEGER NOT NULL DEFAULT 0,
  tax_rate_bp          INTEGER NOT NULL DEFAULT 0,
  tax_minor            INTEGER NOT NULL DEFAULT 0,
  total_minor          INTEGER NOT NULL DEFAULT 0,
  unit_cost_minor      INTEGER NOT NULL DEFAULT 0,
  cost_minor           INTEGER NOT NULL DEFAULT 0,
  is_gift              INTEGER NOT NULL DEFAULT 0 CHECK (is_gift IN (0,1)),
  returned_qty_milli   INTEGER NOT NULL DEFAULT 0,
  note                 TEXT,
  line_no              INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX ix_sales_lines_invoice ON sales_invoice_lines(invoice_id)',
  'CREATE INDEX ix_sales_lines_item ON sales_invoice_lines(item_id)',
  '''
CREATE TABLE sale_tenders (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id  INTEGER NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
  method      TEXT NOT NULL CHECK (method IN ('cash','card','bank','voucher','credit')),
  account_id  INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
  amount_minor INTEGER NOT NULL DEFAULT 0,
  reference   TEXT
)''',
  'CREATE INDEX ix_sale_tenders_invoice ON sale_tenders(invoice_id)',

  // ----------------------------------------------------------- purchases ---
  '''
CREATE TABLE purchase_invoices (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_no             TEXT NOT NULL,
  doc_type               TEXT NOT NULL DEFAULT 'purchase'
                         CHECK (doc_type IN ('purchase','purchase_return')),
  party_id               INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  supplier_ref           TEXT,
  issued_at              TEXT NOT NULL,
  user_id                INTEGER REFERENCES users(id) ON DELETE SET NULL,
  gross_minor            INTEGER NOT NULL DEFAULT 0,
  line_discount_minor    INTEGER NOT NULL DEFAULT 0,
  invoice_discount_minor INTEGER NOT NULL DEFAULT 0,
  discount_total_minor   INTEGER NOT NULL DEFAULT 0,
  fees_minor             INTEGER NOT NULL DEFAULT 0,
  subtotal_minor         INTEGER NOT NULL DEFAULT 0,
  tax_minor              INTEGER NOT NULL DEFAULT 0,
  rounding_minor         INTEGER NOT NULL DEFAULT 0,
  total_minor            INTEGER NOT NULL DEFAULT 0,
  paid_minor             INTEGER NOT NULL DEFAULT 0,
  due_minor              INTEGER NOT NULL DEFAULT 0,
  items_count            INTEGER NOT NULL DEFAULT 0,
  status                 TEXT NOT NULL DEFAULT 'posted'
                         CHECK (status IN ('draft','posted','void','returned','partially_returned')),
  return_of_id           INTEGER REFERENCES purchase_invoices(id) ON DELETE SET NULL,
  journal_entry_id       INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL,
  note                   TEXT,
  created_at             TEXT NOT NULL,
  updated_at             TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_purchase_invoice_no ON purchase_invoices(invoice_no)',
  'CREATE INDEX ix_purchase_issued ON purchase_invoices(issued_at)',
  'CREATE INDEX ix_purchase_party ON purchase_invoices(party_id)',
  '''
CREATE TABLE purchase_invoice_lines (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id             INTEGER NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  item_id                INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  item_unit_id           INTEGER REFERENCES item_units(id) ON DELETE SET NULL,
  unit_name              TEXT NOT NULL DEFAULT '',
  factor_milli           INTEGER NOT NULL DEFAULT 1000,
  qty_milli              INTEGER NOT NULL,
  qty_base_milli         INTEGER NOT NULL,
  unit_cost_minor        INTEGER NOT NULL DEFAULT 0,
  gross_minor            INTEGER NOT NULL DEFAULT 0,
  line_discount_minor    INTEGER NOT NULL DEFAULT 0,
  alloc_discount_minor   INTEGER NOT NULL DEFAULT 0,
  alloc_fee_minor        INTEGER NOT NULL DEFAULT 0,
  net_minor              INTEGER NOT NULL DEFAULT 0,
  landed_total_minor     INTEGER NOT NULL DEFAULT 0,
  landed_unit_cost_minor INTEGER NOT NULL DEFAULT 0,
  tax_rate_bp            INTEGER NOT NULL DEFAULT 0,
  tax_minor              INTEGER NOT NULL DEFAULT 0,
  new_sell_price_minor   INTEGER,
  returned_qty_milli     INTEGER NOT NULL DEFAULT 0,
  note                   TEXT,
  line_no                INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX ix_purchase_lines_invoice ON purchase_invoice_lines(invoice_id)',
  'CREATE INDEX ix_purchase_lines_item ON purchase_invoice_lines(item_id)',

  // ------------------------------------------------------------ payments ---
  '''
CREATE TABLE payments (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_no       TEXT NOT NULL,
  kind             TEXT NOT NULL CHECK (kind IN ('receipt','payment')),
  party_id         INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  paid_at          TEXT NOT NULL,
  method           TEXT NOT NULL DEFAULT 'cash' CHECK (method IN ('cash','card','bank','voucher')),
  account_id       INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  counter_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
  amount_minor     INTEGER NOT NULL CHECK (amount_minor > 0),
  discount_minor   INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
  user_id          INTEGER REFERENCES users(id) ON DELETE SET NULL,
  journal_entry_id INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL,
  reference        TEXT,
  note             TEXT,
  is_void          INTEGER NOT NULL DEFAULT 0 CHECK (is_void IN (0,1)),
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_payments_no ON payments(payment_no)',
  'CREATE INDEX ix_payments_party ON payments(party_id, paid_at)',
  '''
CREATE TABLE payment_allocations (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_id   INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  doc_type     TEXT NOT NULL CHECK (doc_type IN ('sale','purchase')),
  doc_id       INTEGER NOT NULL,
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0)
)''',
  'CREATE INDEX ix_payment_alloc_payment ON payment_allocations(payment_id)',
  'CREATE INDEX ix_payment_alloc_doc ON payment_allocations(doc_type, doc_id)',

  // --------------------------------------------------------- held carts ---
  '''
CREATE TABLE carts (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_no        INTEGER NOT NULL,
  label          TEXT,
  party_id       INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  price_mode     TEXT NOT NULL DEFAULT 'retail' CHECK (price_mode IN ('retail','wholesale')),
  status         TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','held','done')),
  discount_kind  TEXT NOT NULL DEFAULT 'none' CHECK (discount_kind IN ('none','percent','amount')),
  discount_value INTEGER NOT NULL DEFAULT 0,
  tax_rate_bp    INTEGER NOT NULL DEFAULT 0,
  service_charge_minor INTEGER NOT NULL DEFAULT 0,
  note           TEXT,
  user_id        INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
)''',
  "CREATE UNIQUE INDEX ux_carts_slot ON carts(slot_no) WHERE status <> 'done'",
  '''
CREATE TABLE cart_lines (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  cart_id          INTEGER NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  item_id          INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  item_unit_id     INTEGER REFERENCES item_units(id) ON DELETE SET NULL,
  qty_milli        INTEGER NOT NULL DEFAULT 1000,
  unit_price_minor INTEGER NOT NULL DEFAULT 0,
  discount_kind    TEXT NOT NULL DEFAULT 'none' CHECK (discount_kind IN ('none','percent','amount')),
  discount_value   INTEGER NOT NULL DEFAULT 0,
  is_gift          INTEGER NOT NULL DEFAULT 0 CHECK (is_gift IN (0,1)),
  note             TEXT,
  sort_order       INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL
)''',
  'CREATE INDEX ix_cart_lines_cart ON cart_lines(cart_id)',
  'CREATE UNIQUE INDEX ux_cart_lines_item ON cart_lines(cart_id, item_id, item_unit_id, is_gift)',

  // ------------------------------------------------------------ printing ---
  '''
CREATE TABLE printer_profiles (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name            TEXT NOT NULL,
  driver          TEXT NOT NULL CHECK (driver IN ('pdf','system','esc_pos_usb','esc_pos_network','sunmi')),
  paper           TEXT NOT NULL DEFAULT 'roll80' CHECK (paper IN ('roll58','roll80','a4','a5')),
  address         TEXT,
  copies          INTEGER NOT NULL DEFAULT 1 CHECK (copies BETWEEN 1 AND 5),
  header_text     TEXT,
  footer_text     TEXT,
  logo_path       TEXT,
  show_logo       INTEGER NOT NULL DEFAULT 1 CHECK (show_logo IN (0,1)),
  show_barcode    INTEGER NOT NULL DEFAULT 1 CHECK (show_barcode IN (0,1)),
  show_tax_lines  INTEGER NOT NULL DEFAULT 1 CHECK (show_tax_lines IN (0,1)),
  open_drawer     INTEGER NOT NULL DEFAULT 0 CHECK (open_drawer IN (0,1)),
  auto_print      INTEGER NOT NULL DEFAULT 1 CHECK (auto_print IN (0,1)),
  font_scale_bp   INTEGER NOT NULL DEFAULT 10000,
  is_default      INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
  is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
)''',

  // ----------------------------------------------------------- audit log ---
  '''
CREATE TABLE audit_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  happened_at TEXT NOT NULL,
  user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  action     TEXT NOT NULL,
  entity     TEXT NOT NULL,
  entity_id  INTEGER,
  detail     TEXT
)''',
  'CREATE INDEX ix_audit_when ON audit_log(happened_at)',

  // --------------------------------------------------------------- views ---
  // Every reporting view derives from the journal or the stock ledger. None of
  // them mentions an account id — they resolve accounts by type or system_key.
  '''
CREATE VIEW v_account_balances AS
SELECT a.id                AS account_id,
       a.code,
       a.name,
       a.type,
       a.normal_side,
       a.parent_id,
       a.system_key,
       IFNULL(SUM(l.debit_minor), 0)  AS debit_minor,
       IFNULL(SUM(l.credit_minor), 0) AS credit_minor,
       CASE WHEN a.normal_side = 'debit'
            THEN IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0)
            ELSE IFNULL(SUM(l.credit_minor), 0) - IFNULL(SUM(l.debit_minor), 0)
       END AS balance_minor
  FROM accounts a
  LEFT JOIN journal_lines l   ON l.account_id = a.id
  LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
 WHERE a.is_active = 1
 GROUP BY a.id''',
  '''
CREATE VIEW v_general_ledger AS
SELECT l.id            AS line_id,
       e.id            AS entry_id,
       e.entry_no,
       e.entry_date,
       e.posted_at,
       e.source_type,
       e.source_id,
       e.memo          AS entry_memo,
       l.memo          AS line_memo,
       l.account_id,
       a.code          AS account_code,
       a.name          AS account_name,
       a.type          AS account_type,
       l.party_id,
       p.name          AS party_name,
       l.debit_minor,
       l.credit_minor,
       u.full_name     AS user_name
  FROM journal_lines l
  JOIN journal_entries e ON e.id = l.entry_id
  JOIN accounts a        ON a.id = l.account_id
  LEFT JOIN parties p    ON p.id = l.party_id
  LEFT JOIN users u      ON u.id = e.user_id
 WHERE e.is_void = 0''',
  '''
CREATE VIEW v_trial_balance AS
SELECT account_id,
       code,
       name,
       type,
       normal_side,
       debit_minor,
       credit_minor,
       CASE WHEN debit_minor - credit_minor > 0
            THEN debit_minor - credit_minor ELSE 0 END AS debit_balance_minor,
       CASE WHEN credit_minor - debit_minor > 0
            THEN credit_minor - debit_minor ELSE 0 END AS credit_balance_minor
  FROM v_account_balances
 WHERE debit_minor <> 0 OR credit_minor <> 0''',
  '''
CREATE VIEW v_unbalanced_entries AS
SELECT e.id AS entry_id,
       e.entry_no,
       e.entry_date,
       SUM(l.debit_minor)  AS debit_minor,
       SUM(l.credit_minor) AS credit_minor,
       SUM(l.debit_minor) - SUM(l.credit_minor) AS difference_minor
  FROM journal_entries e
  JOIN journal_lines l ON l.entry_id = e.id
 GROUP BY e.id
HAVING SUM(l.debit_minor) <> SUM(l.credit_minor)''',
  '''
CREATE VIEW v_party_balances AS
SELECT p.id   AS party_id,
       p.name,
       p.kind,
       p.phone,
       p.account_id,
       a.code  AS account_code,
       IFNULL(SUM(l.debit_minor), 0)  AS debit_minor,
       IFNULL(SUM(l.credit_minor), 0) AS credit_minor,
       IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0) AS balance_minor
  FROM parties p
  LEFT JOIN accounts a        ON a.id = p.account_id
  LEFT JOIN journal_lines l   ON l.account_id = p.account_id
  LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
 GROUP BY p.id''',
  '''
CREATE VIEW v_items_full AS
SELECT i.*,
       c.name AS category_name,
       bu.name AS base_unit_name,
       (SELECT iu.sell_price_minor FROM item_units iu
         WHERE iu.item_id = i.id
         ORDER BY iu.is_default_sale DESC, iu.is_base DESC, iu.sort_order LIMIT 1)
         AS default_sell_price_minor,
       (SELECT iu.barcode FROM item_units iu
         WHERE iu.item_id = i.id AND iu.barcode IS NOT NULL AND iu.barcode <> ''
         ORDER BY iu.is_base DESC, iu.sort_order LIMIT 1) AS primary_barcode,
       (SELECT COUNT(*) FROM item_units iu WHERE iu.item_id = i.id) AS unit_count,
       (i.stock_qty_milli * i.avg_cost_minor) / 1000 AS stock_value_minor
  FROM items i
  LEFT JOIN categories c ON c.id = i.category_id
  LEFT JOIN units bu     ON bu.id = i.base_unit_id''',
  '''
CREATE VIEW v_inventory_movements AS
SELECT m.id,
       m.moved_at,
       m.kind,
       m.item_id,
       i.name AS item_name,
       u.name AS base_unit_name,
       m.qty_milli,
       m.unit_cost_minor,
       m.cost_total_minor,
       m.balance_after_milli,
       m.doc_type,
       m.doc_id,
       m.note
  FROM stock_moves m
  JOIN items i ON i.id = m.item_id
  LEFT JOIN units u ON u.id = i.base_unit_id''',
  '''
CREATE VIEW v_item_stock_summary AS
SELECT i.id AS item_id,
       i.name,
       i.stock_qty_milli,
       i.avg_cost_minor,
       (i.stock_qty_milli * i.avg_cost_minor) / 1000 AS stock_value_minor,
       IFNULL(SUM(CASE WHEN m.kind IN ('purchase','opening')  THEN m.qty_milli END), 0) AS in_qty_milli,
       IFNULL(SUM(CASE WHEN m.kind = 'sale'                   THEN -m.qty_milli END), 0) AS sold_qty_milli,
       IFNULL(SUM(CASE WHEN m.kind = 'sale_return'            THEN m.qty_milli END), 0) AS sale_return_qty_milli,
       IFNULL(SUM(CASE WHEN m.kind = 'purchase_return'        THEN -m.qty_milli END), 0) AS purchase_return_qty_milli,
       IFNULL(SUM(CASE WHEN m.kind IN ('waste','adjustment')  THEN m.qty_milli END), 0) AS adjust_qty_milli
  FROM items i
  LEFT JOIN stock_moves m ON m.item_id = i.id
 GROUP BY i.id''',
  '''
CREATE VIEW v_sales_invoices_full AS
SELECT s.*,
       p.name      AS party_name,
       p.phone     AS party_phone,
       u.full_name AS cashier_name
  FROM sales_invoices s
  LEFT JOIN parties p ON p.id = s.party_id
  LEFT JOIN users u   ON u.id = s.user_id''',
  '''
CREATE VIEW v_purchase_invoices_full AS
SELECT b.*,
       p.name      AS party_name,
       p.phone     AS party_phone,
       u.full_name AS user_name
  FROM purchase_invoices b
  LEFT JOIN parties p ON p.id = b.party_id
  LEFT JOIN users u   ON u.id = b.user_id''',
  '''
CREATE VIEW v_daily_sales AS
SELECT substr(issued_at, 1, 10) AS day,
       COUNT(*)                 AS invoice_count,
       SUM(CASE WHEN doc_type = 'sale' THEN total_minor ELSE -total_minor END)   AS total_minor,
       SUM(CASE WHEN doc_type = 'sale' THEN cost_minor  ELSE -cost_minor  END)   AS cost_minor,
       SUM(CASE WHEN doc_type = 'sale' THEN profit_minor ELSE -profit_minor END) AS profit_minor,
       SUM(discount_total_minor) AS discount_minor,
       SUM(tax_minor)            AS tax_minor
  FROM sales_invoices
 WHERE status <> 'void'
 GROUP BY day''',
  '''
CREATE VIEW v_income_statement AS
SELECT a.type,
       a.code,
       a.name,
       a.system_key,
       CASE WHEN a.type = 'revenue'
            THEN IFNULL(SUM(l.credit_minor), 0) - IFNULL(SUM(l.debit_minor), 0)
            ELSE IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0)
       END AS amount_minor
  FROM accounts a
  LEFT JOIN journal_lines l   ON l.account_id = a.id
  LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
 WHERE a.type IN ('revenue','expense') AND a.is_group = 0
 GROUP BY a.id''',
  '''
CREATE VIEW v_balance_sheet AS
SELECT type,
       code,
       name,
       system_key,
       balance_minor
  FROM v_account_balances
 WHERE type IN ('asset','liability','equity')''',
];
