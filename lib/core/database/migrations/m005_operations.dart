/// Schema version 4 — the parts of a shop that are not a single sale.
///
/// Seven additions, each one a thing a shopkeeper does that the software could
/// not yet describe:
///
/// * **Batches and expiry.** Yoghurt bought twice is two batches with two
///   dates, and the one that expires first must leave first.
/// * **Purchase orders.** What was ordered, what arrived, and what is still
///   owed by the supplier — separate from the invoice that eventually lands.
/// * **Stocktakes.** A counting sheet filled in over a morning and posted once,
///   rather than fifty separate adjustments.
/// * **Promotions.** "Three for the price of two", a weekend 10 % off, a
///   cheaper price when you buy a box.
/// * **Loyalty.** Points earned on what a customer spends and taken off a later
///   bill.
/// * **Permissions.** What each role may reach, decided by the owner rather
///   than by the code.
/// * **Backups.** Where the automatic copies go and how many are kept.
///
/// ## The decision worth explaining: batches do not change costing
///
/// It is tempting to make batches the cost layer — FIFO, each batch carrying
/// its own price. That would replace the moving average the whole ledger,
/// every report and every verified test is built on, and it would make the
/// cost of a sale depend on which physical box the cashier reached for.
///
/// So batches here answer *quantity and date* only: how many of this item, in
/// which batch, expiring when. The **cost of a sale stays the moving average**,
/// exactly as before. A shop gets expiry control and traceability without the
/// books changing meaning, and `stock_moves` remains the one record of value.
library;

const List<String> schemaV4 = <String>[
  // ---------------------------------------------------------- batches ----
  "ALTER TABLE items ADD COLUMN track_batches INTEGER NOT NULL DEFAULT 0 CHECK (track_batches IN (0,1))",

  '''
CREATE TABLE item_batches (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id         INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,

  -- What the supplier printed on the box. Blank when a shop tracks only dates.
  batch_no        TEXT    NOT NULL DEFAULT '',

  production_date TEXT,
  expiry_date     TEXT,

  -- Kept as a cache the way items.stock_qty_milli is: maintained by the
  -- triggers below, never written by hand.
  qty_milli       INTEGER NOT NULL DEFAULT 0,

  -- What this batch cost when it arrived. Informational: the ledger values
  -- stock at the moving average, and this is here so a shop can see what it
  -- paid for the box in front of it.
  unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost_minor >= 0),

  party_id        INTEGER REFERENCES parties(id) ON DELETE SET NULL,
  received_at     TEXT    NOT NULL,
  doc_type        TEXT,
  doc_id          INTEGER,
  note            TEXT,
  is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL
)''',

  // One batch per item per number-and-date: buying the same lot twice adds to
  // it rather than creating a second row that splits the shelf in the report.
  '''CREATE UNIQUE INDEX ux_batch_identity
       ON item_batches(item_id, batch_no, IFNULL(expiry_date, ''))''',
  'CREATE INDEX ix_batch_item ON item_batches(item_id, expiry_date)',
  'CREATE INDEX ix_batch_expiry ON item_batches(expiry_date) WHERE expiry_date IS NOT NULL',

  'ALTER TABLE stock_moves ADD COLUMN batch_id INTEGER REFERENCES item_batches(id) ON DELETE SET NULL',
  'CREATE INDEX ix_moves_batch ON stock_moves(batch_id)',

  // The batch cache, maintained the same way the item cache is — by the
  // database, so nothing that moves stock can forget to update it.
  '''
CREATE TRIGGER trg_batch_qty_insert
AFTER INSERT ON stock_moves
FOR EACH ROW WHEN NEW.batch_id IS NOT NULL
BEGIN
  UPDATE item_batches
     SET qty_milli = qty_milli + NEW.qty_milli,
         updated_at = NEW.moved_at
   WHERE id = NEW.batch_id;
END''',
  '''
CREATE TRIGGER trg_batch_qty_delete
AFTER DELETE ON stock_moves
FOR EACH ROW WHEN OLD.batch_id IS NOT NULL
BEGIN
  UPDATE item_batches
     SET qty_milli = qty_milli - OLD.qty_milli
   WHERE id = OLD.batch_id;
END''',

  // Which batches are still on the shelf, soonest expiry first — the order
  // stock should leave in, and the order the expiry report reads in.
  '''
CREATE VIEW v_batch_stock AS
SELECT b.id            AS batch_id,
       b.item_id,
       i.name          AS item_name,
       i.sku,
       b.batch_no,
       b.expiry_date,
       b.production_date,
       b.qty_milli,
       b.unit_cost_minor,
       b.party_id,
       p.name          AS party_name,
       b.received_at,
       CASE
         WHEN b.expiry_date IS NULL THEN NULL
         WHEN b.expiry_date < DATE('now') THEN -1
         ELSE CAST(julianday(b.expiry_date) - julianday(DATE('now')) AS INTEGER)
       END             AS days_left
  FROM item_batches b
  JOIN items i   ON i.id = b.item_id
  LEFT JOIN parties p ON p.id = b.party_id
 WHERE b.qty_milli > 0 AND b.is_active = 1''',

  // ---------------------------------------------------- purchase orders ---
  '''
CREATE TABLE purchase_orders (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  order_no         TEXT    NOT NULL,
  party_id         INTEGER NOT NULL REFERENCES parties(id) ON DELETE RESTRICT,
  ordered_at       TEXT    NOT NULL,
  expected_at      TEXT,
  user_id          INTEGER REFERENCES users(id) ON DELETE SET NULL,
  status           TEXT    NOT NULL DEFAULT 'draft'
                           CHECK (status IN ('draft','sent','partial','received','cancelled')),
  total_minor      INTEGER NOT NULL DEFAULT 0,
  items_count      INTEGER NOT NULL DEFAULT 0,
  note             TEXT,
  created_at       TEXT    NOT NULL,
  updated_at       TEXT    NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_order_no ON purchase_orders(order_no)',
  'CREATE INDEX ix_order_party ON purchase_orders(party_id, ordered_at)',

  '''
CREATE TABLE purchase_order_lines (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id         INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  item_id          INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  item_unit_id     INTEGER REFERENCES item_units(id) ON DELETE SET NULL,
  unit_name        TEXT    NOT NULL DEFAULT '',
  factor_milli     INTEGER NOT NULL DEFAULT 1000,
  qty_milli        INTEGER NOT NULL CHECK (qty_milli > 0),

  -- How much of the order has actually arrived. A supplier who sends half the
  -- order leaves the rest outstanding rather than closing it.
  received_qty_milli INTEGER NOT NULL DEFAULT 0 CHECK (received_qty_milli >= 0),

  unit_cost_minor  INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost_minor >= 0),
  total_minor      INTEGER NOT NULL DEFAULT 0,
  note             TEXT,
  line_no          INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX ix_order_lines ON purchase_order_lines(order_id)',

  // The invoice that fulfilled an order, so the two can be read together.
  'ALTER TABLE purchase_invoices ADD COLUMN order_id INTEGER REFERENCES purchase_orders(id) ON DELETE SET NULL',

  '''
CREATE VIEW v_purchase_orders_full AS
SELECT o.*,
       p.name AS party_name,
       u.full_name AS user_name,
       (SELECT IFNULL(SUM(l.qty_milli), 0)
          FROM purchase_order_lines l WHERE l.order_id = o.id) AS ordered_milli,
       (SELECT IFNULL(SUM(l.received_qty_milli), 0)
          FROM purchase_order_lines l WHERE l.order_id = o.id) AS received_milli
  FROM purchase_orders o
  JOIN parties p ON p.id = o.party_id
  LEFT JOIN users u ON u.id = o.user_id''',

  // What each supplier last charged for each item, and the best price anyone
  // ever charged — the two numbers you want in front of you when ordering.
  '''
CREATE VIEW v_supplier_prices AS
SELECT l.item_id,
       i.name        AS item_name,
       v.party_id,
       p.name        AS party_name,
       COUNT(*)      AS times_bought,
       MAX(v.issued_at) AS last_bought_at,
       (SELECT l2.unit_cost_minor
          FROM purchase_invoice_lines l2
          JOIN purchase_invoices v2 ON v2.id = l2.invoice_id
         WHERE l2.item_id = l.item_id AND v2.party_id = v.party_id
           AND v2.status <> 'void' AND v2.doc_type = 'purchase'
         ORDER BY v2.issued_at DESC, l2.id DESC LIMIT 1) AS last_cost_minor,
       MIN(l.unit_cost_minor) AS best_cost_minor
  FROM purchase_invoice_lines l
  JOIN purchase_invoices v ON v.id = l.invoice_id
  JOIN items i   ON i.id = l.item_id
  JOIN parties p ON p.id = v.party_id
 WHERE v.status <> 'void' AND v.doc_type = 'purchase'
 GROUP BY l.item_id, v.party_id''',

  // -------------------------------------------------------- stocktakes ---
  '''
CREATE TABLE stock_counts (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  count_no       TEXT    NOT NULL,
  started_at     TEXT    NOT NULL,
  finished_at    TEXT,
  user_id        INTEGER REFERENCES users(id) ON DELETE SET NULL,
  category_id    INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  scope          TEXT    NOT NULL DEFAULT 'all'
                         CHECK (scope IN ('all','category','selection')),
  status         TEXT    NOT NULL DEFAULT 'open'
                         CHECK (status IN ('open','posted','cancelled')),

  -- What the variance was worth, filled in when the count is posted.
  variance_value_minor INTEGER NOT NULL DEFAULT 0,
  journal_entry_id INTEGER REFERENCES journal_entries(id) ON DELETE SET NULL,
  note           TEXT,
  created_at     TEXT    NOT NULL,
  updated_at     TEXT    NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_count_no ON stock_counts(count_no)',

  '''
CREATE TABLE stock_count_lines (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  count_id      INTEGER NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  item_id       INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,

  -- What the system believed when the sheet was made. Frozen on purpose: the
  -- variance a manager signs off is the one the counter actually faced, not
  -- one recomputed after the shop kept selling.
  system_qty_milli INTEGER NOT NULL DEFAULT 0,

  -- Null until somebody counts it, which is what "not counted yet" means.
  counted_qty_milli INTEGER,

  unit_cost_minor INTEGER NOT NULL DEFAULT 0,
  note          TEXT,
  counted_at    TEXT,
  counted_by    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  line_no       INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE UNIQUE INDEX ux_count_line ON stock_count_lines(count_id, item_id)',

  '''
CREATE VIEW v_stock_count_lines AS
SELECT l.*,
       i.name AS item_name,
       i.sku,
       u.name AS unit_name,
       CASE WHEN l.counted_qty_milli IS NULL THEN NULL
            ELSE l.counted_qty_milli - l.system_qty_milli END AS variance_milli,
       CASE WHEN l.counted_qty_milli IS NULL THEN 0
            ELSE ((l.counted_qty_milli - l.system_qty_milli) * l.unit_cost_minor) / 1000
       END AS variance_value_minor
  FROM stock_count_lines l
  JOIN items i ON i.id = l.item_id
  LEFT JOIN units u ON u.id = i.base_unit_id''',

  // ------------------------------------------------------- promotions ----
  '''
CREATE TABLE promotions (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  name           TEXT    NOT NULL,
  name_ar        TEXT,
  name_ku        TEXT,

  -- percent   — a share off the line
  -- amount    — a fixed sum off the line
  -- price     — a replacement unit price
  -- quantity  — a cheaper unit price once you buy enough
  -- buy_get   — buy X, get Y of the same item free
  kind           TEXT    NOT NULL
                         CHECK (kind IN ('percent','amount','price','quantity','buy_get')),

  value_bp       INTEGER NOT NULL DEFAULT 0 CHECK (value_bp >= 0),
  value_minor    INTEGER NOT NULL DEFAULT 0 CHECK (value_minor >= 0),
  min_qty_milli  INTEGER NOT NULL DEFAULT 0 CHECK (min_qty_milli >= 0),
  get_qty_milli  INTEGER NOT NULL DEFAULT 0 CHECK (get_qty_milli >= 0),

  -- Empty means every item; rows in promotion_items narrow it.
  scope          TEXT    NOT NULL DEFAULT 'items'
                         CHECK (scope IN ('items','category','all')),
  category_id    INTEGER REFERENCES categories(id) ON DELETE CASCADE,

  starts_on      TEXT,
  ends_on        TEXT,

  -- Days of the week it runs on, as digits: '' is every day, '56' is a
  -- weekend offer. SQLite's strftime('%w') numbering, Sunday = 0.
  weekdays       TEXT    NOT NULL DEFAULT '',

  price_mode     TEXT    NOT NULL DEFAULT 'any'
                         CHECK (price_mode IN ('any','retail','wholesale')),

  -- A customer-only offer, when the shop runs a members' price.
  members_only   INTEGER NOT NULL DEFAULT 0 CHECK (members_only IN (0,1)),

  priority       INTEGER NOT NULL DEFAULT 0,
  is_active      INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at     TEXT    NOT NULL,
  updated_at     TEXT    NOT NULL
)''',
  'CREATE INDEX ix_promo_active ON promotions(is_active, starts_on, ends_on)',

  '''
CREATE TABLE promotion_items (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  promotion_id INTEGER NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  item_id      INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE
)''',
  'CREATE UNIQUE INDEX ux_promo_item ON promotion_items(promotion_id, item_id)',

  // Which promotion was applied to which line, so a discount on a receipt can
  // always be explained a month later.
  'ALTER TABLE sales_invoice_lines ADD COLUMN promotion_id INTEGER REFERENCES promotions(id) ON DELETE SET NULL',

  '''
CREATE VIEW v_active_promotions AS
SELECT p.*,
       (SELECT COUNT(*) FROM promotion_items pi WHERE pi.promotion_id = p.id) AS item_count
  FROM promotions p
 WHERE p.is_active = 1
   AND (p.starts_on IS NULL OR p.starts_on <= DATE('now'))
   AND (p.ends_on   IS NULL OR p.ends_on   >= DATE('now'))''',

  // ---------------------------------------------------------- loyalty ----
  '''
CREATE TABLE loyalty_ledger (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  party_id     INTEGER NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
  happened_at  TEXT    NOT NULL,

  -- Positive when points are earned, negative when they are spent. Points are
  -- whole numbers: a scheme nobody can compute in their head is a scheme
  -- customers do not trust.
  points       INTEGER NOT NULL,

  kind         TEXT    NOT NULL CHECK (kind IN ('earn','redeem','adjust','expire')),
  doc_type     TEXT,
  doc_id       INTEGER,
  user_id      INTEGER REFERENCES users(id) ON DELETE SET NULL,
  note         TEXT
)''',
  'CREATE INDEX ix_loyalty_party ON loyalty_ledger(party_id, happened_at)',

  // What a sale gave and took, kept on the invoice so a receipt can print it.
  'ALTER TABLE sales_invoices ADD COLUMN points_earned INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE sales_invoices ADD COLUMN points_spent INTEGER NOT NULL DEFAULT 0',

  '''
CREATE VIEW v_loyalty_balances AS
SELECT p.id AS party_id,
       p.name,
       IFNULL(SUM(l.points), 0) AS points,
       MAX(l.happened_at)       AS last_activity
  FROM parties p
  LEFT JOIN loyalty_ledger l ON l.party_id = p.id
 GROUP BY p.id''',

  // ------------------------------------------------------ permissions ----
  '''
CREATE TABLE role_permissions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  role       TEXT    NOT NULL CHECK (role IN ('owner','manager','cashier','accountant')),
  permission TEXT    NOT NULL,
  allowed    INTEGER NOT NULL DEFAULT 1 CHECK (allowed IN (0,1)),
  updated_at TEXT    NOT NULL
)''',
  'CREATE UNIQUE INDEX ux_role_permission ON role_permissions(role, permission)',

  // The owner is not a role that can be locked out of its own shop.
  '''
CREATE TRIGGER trg_owner_keeps_permissions
BEFORE UPDATE ON role_permissions
FOR EACH ROW WHEN NEW.role = 'owner' AND NEW.allowed = 0
BEGIN
  SELECT RAISE(ABORT, 'the owner cannot be locked out');
END''',

  // ------------------------------------------------- reporting views ----
  // What has not sold, with what it is worth sitting there. The date of the
  // last sale is the whole point: "no sales in 90 days" is a question about
  // when, not about how many.
  '''
CREATE VIEW v_item_activity AS
SELECT i.id                AS item_id,
       i.name              AS item_name,
       i.sku,
       i.category_id,
       c.name              AS category_name,
       i.stock_qty_milli,
       i.avg_cost_minor,
       (i.stock_qty_milli * i.avg_cost_minor) / 1000 AS stock_value_minor,
       i.reorder_level_milli,
       (SELECT MAX(v.issued_at)
          FROM sales_invoice_lines l
          JOIN sales_invoices v ON v.id = l.invoice_id
         WHERE l.item_id = i.id AND v.doc_type = 'sale'
           AND v.status <> 'void')                    AS last_sold_at,
       IFNULL((SELECT SUM(l.qty_base_milli)
          FROM sales_invoice_lines l
          JOIN sales_invoices v ON v.id = l.invoice_id
         WHERE l.item_id = i.id AND v.doc_type = 'sale'
           AND v.status <> 'void'
           AND v.issued_at >= datetime('now', '-30 day')), 0) AS sold_30d_milli,
       IFNULL((SELECT SUM(l.net_minor - l.cost_minor)
          FROM sales_invoice_lines l
          JOIN sales_invoices v ON v.id = l.invoice_id
         WHERE l.item_id = i.id AND v.doc_type = 'sale'
           AND v.status <> 'void'
           AND v.issued_at >= datetime('now', '-30 day')), 0) AS profit_30d_minor,
       IFNULL((SELECT SUM(l.net_minor)
          FROM sales_invoice_lines l
          JOIN sales_invoices v ON v.id = l.invoice_id
         WHERE l.item_id = i.id AND v.doc_type = 'sale'
           AND v.status <> 'void'
           AND v.issued_at >= datetime('now', '-30 day')), 0) AS revenue_30d_minor
  FROM items i
  LEFT JOIN categories c ON c.id = i.category_id
 WHERE i.is_active = 1 AND i.kind IN ('stock','bundle')''',

  // When the shop is busy. Reading this is how a shopkeeper decides when to
  // put a second person on the till.
  '''
CREATE VIEW v_sales_by_hour AS
SELECT CAST(strftime('%H', v.issued_at) AS INTEGER) AS hour_of_day,
       COUNT(*)                                     AS sales_count,
       IFNULL(SUM(v.total_minor), 0)                AS total_minor,
       IFNULL(SUM(v.profit_minor), 0)               AS profit_minor
  FROM sales_invoices v
 WHERE v.doc_type = 'sale' AND v.status <> 'void'
 GROUP BY hour_of_day''',
];

/// Settings introduced with schema v4.
const Map<String, String> settingsV4 = <String, String>{
  // ---- backups ----
  'backup_auto': '0',
  'backup_folder': '',
  // Hours between automatic copies.
  'backup_every_hours': '24',
  // How many copies to keep before the oldest is deleted.
  'backup_keep': '14',
  'backup_last_at': '',

  // ---- loyalty ----
  'loyalty_enabled': '0',
  // Money that earns one point, in minor units: 100000 = one point per 1,000.
  'loyalty_earn_per_minor': '100000',
  // What one point is worth when spent, in minor units.
  'loyalty_point_value_minor': '100',
  'loyalty_min_redeem_points': '100',

  // ---- expiry ----
  // Days ahead that count as "expiring soon" on the report and at the till.
  'expiry_warn_days': '30',

  // ---- selling floor ----
  // '1' — a cashier may not sell under an item's minimum price.
  'enforce_min_price': '1',

  'schema_notes': 'v4',
};

/// The accounts v4 needs, as `system_key → (code, English, Arabic, Kurdish,
/// type, normal side, parent code)`.
///
/// One account, and it earns its place: what the points scheme costs. Points
/// are not booked as a liability when they are earned — see
/// `core/loyalty/loyalty_service.dart` for why — so this is where the cost
/// lands the day a customer actually spends them, on its own line of the
/// income statement where an owner can see whether the scheme is worth it.
const Map<String, List<String>> accountsV4 = <String, List<String>>{
  'loyalty_redeemed': <String>[
    '5085',
    'Loyalty points redeemed',
    'نقاط الولاء المستخدمة',
    'خاڵی دڵسۆزی بەکارهێنراو',
    'expense',
    'debit',
    '5',
  ],
};

/// The permission keys, and which roles get them on a fresh database.
///
/// The owner is deliberately absent: an owner has every permission by
/// definition and cannot be edited, which is what keeps a shop from locking
/// itself out of its own books.
const Map<String, List<String>> defaultPermissions = <String, List<String>>{
  // key: the roles that start with it allowed
  'pos.use': <String>['manager', 'cashier'],
  'pos.discount': <String>['manager'],
  'pos.below_min_price': <String>['manager'],
  'pos.void': <String>['manager'],
  'pos.return': <String>['manager', 'cashier'],
  'items.view': <String>['manager', 'accountant', 'cashier'],
  'items.edit': <String>['manager'],
  'items.cost': <String>['manager', 'accountant'],
  'purchases.view': <String>['manager', 'accountant'],
  'purchases.edit': <String>['manager'],
  'orders.edit': <String>['manager'],
  'stock.adjust': <String>['manager'],
  'stock.count': <String>['manager'],
  'parties.view': <String>['manager', 'accountant', 'cashier'],
  'parties.edit': <String>['manager'],
  'reports.view': <String>['manager', 'accountant'],
  'reports.profit': <String>['manager', 'accountant'],
  'accounting.view': <String>['accountant', 'manager'],
  'accounting.post': <String>['accountant'],
  'shifts.close_other': <String>['manager'],
  'promotions.edit': <String>['manager'],
  'settings.edit': <String>[],
  'users.edit': <String>[],
  'audit.view': <String>['manager'],
};
