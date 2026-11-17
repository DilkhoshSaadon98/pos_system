/// Schema v5 — what a price used to be, and who is late paying.
///
/// Two things a shop asks that the previous schema could not answer. The first
/// is "what did this cost last month", which the audit log almost answers: it
/// records that an item was saved, not what the number was before. The second
/// is "how old is this debt", which needs the invoices behind a balance rather
/// than the balance itself.
///
/// The price trail is kept by **trigger**, not by the code that saves an item.
/// A price can be changed from the item form, from a purchase that updates the
/// sell price, from an import, and one day from something not written yet; a
/// trigger is the only place that catches all four. The user behind the change
/// comes from `app_session`, a one-row table the app stamps at sign-in — the
/// database has no other way to know who is at the till.
const List<String> schemaV5 = <String>[
  '''
CREATE TABLE app_session (
  id      INTEGER PRIMARY KEY CHECK (id = 1),
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  since   TEXT
)''',
  "INSERT OR IGNORE INTO app_session(id, user_id, since) VALUES (1, NULL, NULL)",

  '''
CREATE TABLE price_changes (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id      INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  item_unit_id INTEGER,

  -- Which of the three prices moved.
  field        TEXT NOT NULL CHECK (field IN ('sell','wholesale','min')),

  old_minor    INTEGER NOT NULL DEFAULT 0,
  new_minor    INTEGER NOT NULL DEFAULT 0,

  -- Whoever was signed in, from `app_session`. Null when nobody was — an
  -- import running before the first login, for instance.
  user_id      INTEGER REFERENCES users(id) ON DELETE SET NULL,
  changed_at   TEXT NOT NULL
)''',
  'CREATE INDEX ix_price_changes_item ON price_changes(item_id, changed_at)',

  // One trigger per price rather than one with three branches: SQLite gives no
  // way to insert a variable number of rows from a single trigger body, and
  // three small triggers are easier to read than one clever one.
  '''
CREATE TRIGGER trg_price_sell AFTER UPDATE OF sell_price_minor ON item_units
WHEN OLD.sell_price_minor <> NEW.sell_price_minor
BEGIN
  INSERT INTO price_changes
    (item_id, item_unit_id, field, old_minor, new_minor, user_id, changed_at)
  VALUES (NEW.item_id, NEW.id, 'sell',
          OLD.sell_price_minor, NEW.sell_price_minor,
          (SELECT user_id FROM app_session WHERE id = 1),
          strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'));
END''',
  '''
CREATE TRIGGER trg_price_wholesale
AFTER UPDATE OF wholesale_price_minor ON item_units
WHEN OLD.wholesale_price_minor <> NEW.wholesale_price_minor
BEGIN
  INSERT INTO price_changes
    (item_id, item_unit_id, field, old_minor, new_minor, user_id, changed_at)
  VALUES (NEW.item_id, NEW.id, 'wholesale',
          OLD.wholesale_price_minor, NEW.wholesale_price_minor,
          (SELECT user_id FROM app_session WHERE id = 1),
          strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'));
END''',
  '''
CREATE TRIGGER trg_price_min AFTER UPDATE OF min_price_minor ON item_units
WHEN OLD.min_price_minor <> NEW.min_price_minor
BEGIN
  INSERT INTO price_changes
    (item_id, item_unit_id, field, old_minor, new_minor, user_id, changed_at)
  VALUES (NEW.item_id, NEW.id, 'min',
          OLD.min_price_minor, NEW.min_price_minor,
          (SELECT user_id FROM app_session WHERE id = 1),
          strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'));
END''',

  // The trail, readable: who, which unit, how much it moved.
  '''
CREATE VIEW v_price_history AS
SELECT c.*,
       u.name      AS unit_name,
       usr.full_name AS user_name,
       i.name      AS item_name,
       c.new_minor - c.old_minor AS delta_minor
  FROM price_changes c
  LEFT JOIN items i      ON i.id = c.item_id
  LEFT JOIN item_units iu ON iu.id = c.item_unit_id
  LEFT JOIN units u      ON u.id = iu.unit_id
  LEFT JOIN users usr    ON usr.id = c.user_id''',

  // What the goods have cost over time. Nothing new is stored — every receipt
  // already carries the price paid; this only makes it a question you can ask
  // about one item without reading the whole movement table.
  '''
CREATE VIEW v_cost_history AS
SELECT m.item_id,
       m.moved_at,
       m.kind,
       m.qty_milli,
       m.unit_cost_minor,
       m.doc_type,
       m.doc_id,
       p.name AS party_name
  FROM stock_moves m
  LEFT JOIN purchase_invoices b
         ON m.doc_type = 'purchase' AND b.id = m.doc_id
  LEFT JOIN parties p ON p.id = b.party_id
 WHERE m.kind IN ('purchase','opening','adjustment')
   AND m.unit_cost_minor > 0''',

  // Every invoice that went out on account and has not been fully settled at
  // the moment it was issued. Ageing itself is worked out in Dart: a payment
  // in this app settles a *balance*, not a numbered invoice, so which invoice
  // is still open is a decision (oldest first) rather than a fact, and a
  // decision belongs in code that can be read and tested.
  '''
CREATE VIEW v_customer_invoices_due AS
SELECT s.id            AS invoice_id,
       s.invoice_no,
       s.party_id,
       s.issued_at,
       s.total_minor,
       s.due_minor
  FROM sales_invoices s
 WHERE s.doc_type = 'sale'
   AND s.status <> 'void'
   AND s.party_id IS NOT NULL
   AND s.due_minor > 0''',
];

/// Settings introduced by schema v5.
const Map<String, String> settingsV5 = <String, String>{
  // The customer's screen. Off until a shop has a second monitor to put it on.
  'customer_display': '0',
  'customer_display_port': '8088',
  'customer_display_lan': '0',

  // Refuse a credit sale that would take a customer past their limit. A shop
  // that has never set a limit is unaffected: zero means no limit.
  'enforce_credit_limit': '1',

  // The buckets on the ageing report, in days.
  'ageing_buckets': '30,60,90',
};

/// Permissions introduced by schema v5, and who gets them by default.
///
/// The override is a manager's job, not a cashier's: letting a regular
/// customer go over their limit is a commercial decision, and the point of the
/// limit is that the person at the till cannot make it alone.
const Map<String, List<String>> permissionsV5 = <String, List<String>>{
  'pos.over_credit_limit': <String>['manager'],
};
