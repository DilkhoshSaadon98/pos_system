/// Schema version 2 — the four ways a product can be shaped.
///
/// Version 1 knew one kind of thing: a stocked item priced in one or more
/// units. Real shops sell four:
///
/// * **Stocked goods** — counted on the shelf. Unchanged from v1.
/// * **Services** — delivery, repair, a fitting fee. Nothing leaves the shelf,
///   so no stock movement and no cost of goods; the revenue goes to its own
///   account.
/// * **Bundles** — a meal deal, a gift set. Sold as one line, but what leaves
///   the shelf is the *parts*, each at its own moving-average cost.
/// * **Products with variants** — one shirt in four sizes and three colours.
///
/// The variant decision is the one worth explaining. A variant could have been
/// a new table with its own stock, its own cost and its own barcodes — and then
/// every query, every stock movement, every invoice line and the whole costing
/// engine would need to know whether it was looking at an item or a variant.
/// Instead **a variant is an item**: an ordinary row with `parent_item_id`
/// pointing at a `group` item that is never sold itself. The stock ledger, the
/// moving average, the journal and the invoice lines are untouched, and the
/// only thing that changes is that the till offers a picker when you tap the
/// parent.
///
/// Everything here is additive: no v1 column changes meaning, so a database
/// created by version 1 upgrades by running these statements and nothing else.
library;

const List<String> schemaV2 = <String>[
  // ------------------------------------------------------------- items ---
  // SQLite can only add columns, never constrain them afterwards — the CHECK
  // that would have sat on `kind` is enforced by the two triggers below.
  "ALTER TABLE items ADD COLUMN kind TEXT NOT NULL DEFAULT 'stock'",
  'ALTER TABLE items ADD COLUMN parent_item_id INTEGER REFERENCES items(id) ON DELETE SET NULL',
  'ALTER TABLE items ADD COLUMN variant_name TEXT',
  'ALTER TABLE items ADD COLUMN variant_name_ar TEXT',
  'ALTER TABLE items ADD COLUMN variant_name_ku TEXT',

  // The axis → value map for one variant, as JSON: {"Size":"L","Colour":"Red"}.
  // Stored rather than derived because a shop renames "Colour" to "Shade" one
  // day and the variants that were already priced must keep their identity.
  'ALTER TABLE items ADD COLUMN variant_attrs TEXT',

  'ALTER TABLE items ADD COLUMN is_weighed INTEGER NOT NULL DEFAULT 0',

  // The digits a scale prints inside an embedded-weight barcode. Five digits
  // by convention; kept as text so leading zeros survive.
  'ALTER TABLE items ADD COLUMN scale_code TEXT',

  'CREATE INDEX ix_items_parent ON items(parent_item_id)',
  'CREATE INDEX ix_items_kind ON items(kind, is_active)',
  "CREATE UNIQUE INDEX ux_items_scale_code ON items(scale_code) WHERE scale_code IS NOT NULL AND scale_code <> ''",

  '''
CREATE TRIGGER trg_items_kind_bi BEFORE INSERT ON items
WHEN NEW.kind NOT IN ('stock','service','bundle','group')
BEGIN
  SELECT RAISE(ABORT, 'items.kind must be stock, service, bundle or group');
END''',
  '''
CREATE TRIGGER trg_items_kind_bu BEFORE UPDATE OF kind ON items
WHEN NEW.kind NOT IN ('stock','service','bundle','group')
BEGIN
  SELECT RAISE(ABORT, 'items.kind must be stock, service, bundle or group');
END''',

  // A group holds variants and is never sold; a variant belongs to a group and
  // nothing else. Enforced here rather than in Dart because the importer and
  // any future script write through the same door.
  '''
CREATE TRIGGER trg_items_parent_bi BEFORE INSERT ON items
WHEN NEW.parent_item_id IS NOT NULL
 AND (SELECT kind FROM items WHERE id = NEW.parent_item_id) <> 'group'
BEGIN
  SELECT RAISE(ABORT, 'A variant can only belong to a product marked as a group');
END''',

  // --------------------------------------------------------- variants ---
  '''
CREATE TABLE item_variant_axes (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id    INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  name_ar    TEXT,
  name_ku    TEXT,
  values_csv TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX ix_variant_axes_item ON item_variant_axes(item_id)',

  // ---------------------------------------------------------- bundles ---
  '''
CREATE TABLE item_bundle_components (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  bundle_item_id    INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  component_item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  item_unit_id      INTEGER REFERENCES item_units(id) ON DELETE SET NULL,
  qty_milli         INTEGER NOT NULL CHECK (qty_milli > 0),
  sort_order        INTEGER NOT NULL DEFAULT 0,
  CHECK (bundle_item_id <> component_item_id)
)''',
  'CREATE INDEX ix_bundle_components ON item_bundle_components(bundle_item_id)',
  'CREATE INDEX ix_bundle_component_item ON item_bundle_components(component_item_id)',

  // A bundle inside a bundle would make costing recursive and stock impossible
  // to reason about at the till. One level, enforced at the door.
  '''
CREATE TRIGGER trg_bundle_no_nesting BEFORE INSERT ON item_bundle_components
WHEN (SELECT kind FROM items WHERE id = NEW.component_item_id) IN ('bundle','group')
BEGIN
  SELECT RAISE(ABORT, 'A bundle cannot contain another bundle or a variant group');
END''',

  // ------------------------------------------------- returns plumbing ---
  // A return line points at the line it reverses, which is what lets the goods
  // go back at the cost they left at rather than at today's average — the only
  // way gross profit stays symmetrical.
  'ALTER TABLE sales_invoice_lines ADD COLUMN origin_line_id INTEGER',
  'ALTER TABLE purchase_invoice_lines ADD COLUMN origin_line_id INTEGER',
  'CREATE INDEX ix_sales_lines_origin ON sales_invoice_lines(origin_line_id)',
  'CREATE INDEX ix_purchase_lines_origin ON purchase_invoice_lines(origin_line_id)',

  // Refunds and supplier credits are payments too, so the tender table needs to
  // say which direction the money went.
  "ALTER TABLE sale_tenders ADD COLUMN direction TEXT NOT NULL DEFAULT 'in'",

  // --------------------------------------------------- rebuilt views ---
  'DROP VIEW v_items_full',
  '''
CREATE VIEW v_items_full AS
SELECT i.*,
       c.name  AS category_name,
       bu.name AS base_unit_name,
       parent.name AS parent_name,
       (SELECT iu.sell_price_minor FROM item_units iu
         WHERE iu.item_id = i.id
         ORDER BY iu.is_default_sale DESC, iu.is_base DESC, iu.sort_order LIMIT 1)
         AS default_sell_price_minor,
       (SELECT iu.barcode FROM item_units iu
         WHERE iu.item_id = i.id AND iu.barcode IS NOT NULL AND iu.barcode <> ''
         ORDER BY iu.is_base DESC, iu.sort_order LIMIT 1) AS primary_barcode,
       (SELECT COUNT(*) FROM item_units iu WHERE iu.item_id = i.id) AS unit_count,
       (SELECT COUNT(*) FROM items v WHERE v.parent_item_id = i.id) AS variant_count,
       (SELECT COUNT(*) FROM item_bundle_components b WHERE b.bundle_item_id = i.id)
         AS component_count,
       (i.stock_qty_milli * i.avg_cost_minor) / 1000 AS stock_value_minor,
       -- A group is never sold and never stocked itself; what matters about it
       -- is the total sitting under its variants.
       (SELECT IFNULL(SUM(v.stock_qty_milli), 0) FROM items v
         WHERE v.parent_item_id = i.id) AS variants_stock_milli
  FROM items i
  LEFT JOIN categories c   ON c.id = i.category_id
  LEFT JOIN units bu       ON bu.id = i.base_unit_id
  LEFT JOIN items parent   ON parent.id = i.parent_item_id''',

  // What a bundle costs right now, from its parts' current averages. Read by
  // the till so the profit on a meal deal is honest before it is sold.
  '''
CREATE VIEW v_bundle_costs AS
SELECT b.bundle_item_id                       AS item_id,
       SUM((c.avg_cost_minor *
            (b.qty_milli * IFNULL(iu.factor_milli, 1000) / 1000)) / 1000)
                                              AS cost_minor,
       COUNT(*)                               AS component_count,
       MIN(CASE WHEN c.track_stock = 0 THEN 1
                WHEN c.stock_qty_milli >=
                     (b.qty_milli * IFNULL(iu.factor_milli, 1000) / 1000)
                THEN 1 ELSE 0 END)            AS is_buildable
  FROM item_bundle_components b
  JOIN items c            ON c.id = b.component_item_id
  LEFT JOIN item_units iu ON iu.id = b.item_unit_id
 GROUP BY b.bundle_item_id''',

  // Returns, per original line, so the return screen can show what is left.
  '''
CREATE VIEW v_sale_line_returns AS
SELECT l.id                AS line_id,
       l.invoice_id,
       l.item_id,
       l.qty_milli,
       l.qty_base_milli,
       l.unit_cost_minor,
       l.unit_price_minor,
       l.item_unit_id,
       l.unit_name,
       l.factor_milli,
       l.is_gift,
       IFNULL(l.returned_qty_milli, 0)               AS returned_qty_milli,
       l.qty_milli - IFNULL(l.returned_qty_milli, 0) AS returnable_qty_milli
  FROM sales_invoice_lines l''',
  '''
CREATE VIEW v_purchase_line_returns AS
SELECT l.id                AS line_id,
       l.invoice_id,
       l.item_id,
       l.qty_milli,
       l.qty_base_milli,
       l.landed_unit_cost_minor,
       l.unit_cost_minor,
       l.item_unit_id,
       l.unit_name,
       l.factor_milli,
       IFNULL(l.returned_qty_milli, 0)               AS returned_qty_milli,
       l.qty_milli - IFNULL(l.returned_qty_milli, 0) AS returnable_qty_milli
  FROM purchase_invoice_lines l''',

  // The income statement grouped the way a person reads it, with cost of goods
  // separated from the running expenses so gross profit is a real figure.
  '''
CREATE VIEW v_income_statement_grouped AS
SELECT CASE
         WHEN a.type = 'revenue' AND a.system_key IN ('sales_returns','sales_discounts')
           THEN 'revenue_contra'
         WHEN a.type = 'revenue' THEN 'revenue'
         WHEN a.system_key IN ('cogs','shrinkage','gifts') THEN 'cogs'
         ELSE 'expense'
       END AS bucket,
       a.id   AS account_id,
       a.code,
       a.name,
       a.system_key,
       -- Positive in every bucket, so the statement reads the way it is
       -- spoken. Returns and discounts sit in revenue accounts but carry
       -- debit balances, so they take the other subtraction.
       CASE WHEN a.type = 'revenue'
                 AND a.system_key NOT IN ('sales_returns','sales_discounts')
            THEN IFNULL(SUM(l.credit_minor), 0) - IFNULL(SUM(l.debit_minor), 0)
            ELSE IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0)
       END AS amount_minor
  FROM accounts a
  LEFT JOIN journal_lines l   ON l.account_id = a.id
  LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
 WHERE a.type IN ('revenue','expense') AND a.is_group = 0
 GROUP BY a.id''',
];

/// Settings introduced with schema v2. Inserted on a fresh database by the
/// seed, and back-filled on an upgrade — a missing key would otherwise read as
/// an empty string and disable the scale reader without saying why.
const Map<String, String> settingsV2 = <String, String>{
  // Which barcode prefixes a scale prints. GS1 reserves 20–29 for in-store
  // codes and every scale in this trade ships inside that range.
  'scale_prefixes': '20,21,22,23,24,25,26,27,28,29',
  // 'weight' — the five digits are grams; 'price' — they are minor units.
  'scale_mode': 'weight',
  'scale_decimals': '3',
  'schema_notes': 'v2',
};
