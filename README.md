# Cashier System v2

A rewrite of the cashier, inventory and accounting app: same business, new
foundations. GetX for state, SQLite for storage, one adaptive UI for Windows and
Android, and arithmetic that can be proved.

---

## Why a rewrite

The previous version worked, but four things in it could not be fixed in place.

| Problem in v1 | What v2 does |
| --- | --- |
| Money was stored as `REAL` and totals were computed in three different places (SQL, the cart controller, the receipt) — the screen and the printout could disagree. | Money is an **integer of minor units**. One calculator produces every figure on an invoice; the screen, the receipt and the ledger read the same object. |
| Stock lived in `item_count`, `item_base_quantity` and `item_details.current_stock` at once, and editing an invoice deleted its transactions but left the stock movements behind. | **One stock ledger** (`stock_moves`) with a trigger-maintained cached quantity. Nothing else may write it. |
| Every cash sale was posted twice — once as `sale`, once as `receipt`, between the same two accounts — so revenue was double-counted. Credit sales were posted against a *customer row id* instead of the customer's account, and credit purchases were posted backwards. | Real **double entry**: `journal_entries` + `journal_lines`, refused unless debits equal credits. Accounts are found by `system_key`, never by a hardcoded id. |
| Queries were built by pasting text-field contents into SQL strings. | Everything is parameterised. |

---

## Running it

This repository holds the Dart source, not the generated platform folders. Ask
Flutter to create them once, then run as usual — `flutter create` on an existing
project only adds what is missing and leaves `lib/` alone.

```bash
cd cashier_system_v2
flutter create . --platforms=windows,android --project-name cashier_system_v2
flutter pub get
flutter analyze
flutter test                # the arithmetic suite
flutter run -d windows      # or -d <android device>
```

First launch creates the database, seeds the chart of accounts, units and
settings, and signs in with **admin / admin**. Change that password before the
till goes on a counter (Settings → users).

The database lives in the app's support directory as `cashier_v2.db`.
Settings → *Backup* copies it wherever you point it.

---

## Bringing the old data across

Settings → **Import the old database** → pick the old `cashier_system.db`.

What comes over: categories, units, items (each with its base unit, its second
unit and its barcodes), customers and suppliers, the whole chart of accounts
with its Arabic names, opening stock valued at last known cost, and the closing
balance of every account as one opening entry. Old sales invoices are copied as
read-only history.

What does **not** come over: the old journal. Its cash sales were double-counted
and its credit purchases were reversed, so replaying it would import the errors.
Balances are taken at face value instead — check them once against your own
records before you start selling.

---

## Architecture

```
lib/
├── core/
│   ├── accounting/     journal.dart (the only thing that writes entries), account_keys.dart
│   ├── bindings/       initial_binding.dart — every repository and controller, wired once
│   ├── calc/           sale_calculator, purchase_calculator, costing, discount
│   ├── database/       app_database.dart, migrations/, legacy_import.dart
│   ├── format/         formatters.dart — the only place that turns integers into text
│   ├── inventory/      stock_service.dart — the only thing that moves stock
│   ├── localization/   app_translations.dart (en · ar · ckb)
│   ├── money/          money.dart (Money, Qty), arithmetic.dart (rounding, allocation)
│   ├── theme/          app_colors, app_theme, responsive
│   ├── utils/          time.dart, security.dart
│   └── widgets/        admin_table, app_widgets (cards, chips, modals, fields)
└── features/
    ├── auth/       catalog/     dashboard/   parties/
    ├── pos/        printing/    purchases/   sales/
    ├── settings/   shell/
```

Each feature is `data/` (repositories that talk to SQLite), `domain/` (plain
entities) and `presentation/` (a GetX controller plus its pages) — the layout of
the admin panel this was modelled on, with GetX controllers where that project
uses cubits.

**State:** `GetxController` + `Obx`. Controllers hold no derived totals; they
recompute from the calculators, so a total can never go stale.

**Responsive:** one widget per screen. Desktop gets the sidebar and wide tables,
tablets an icon rail, phones a drawer, a bottom bar and record cards. The till
puts the cart beside the products on a wide screen and behind a bottom sheet on
a narrow one.

**Languages:** English, Arabic and Kurdish Sorani, switched at runtime, with
right-to-left handled once in `main.dart`.

---

## The arithmetic

Three rules the whole system rests on:

1. **Money is an integer of minor units** (1/100 of the currency). `1 500 IQD`
   is `150000`. Columns end in `_minor`.
2. **Quantities are integers of thousandths**, so 0.25 kg is `250`. Columns end
   in `_milli`.
3. **Percentages are basis points.** 7.5 % is `750`. Columns end in `_bp`.

### How a sale is priced

1. Line gross = unit price × quantity.
2. Line discount — a percentage of that line, or a typed amount, never more than
   the line. A gift is a 100 % discount.
3. Invoice discount — worked out on the sum of the discounted lines, then
   **allocated back onto the lines** by the largest-remainder method, exactly.
   Every line therefore knows what it really sold for, so per-item profit stays
   honest when the cashier rounds the whole bill down.
4. Tax per line, on the line's final net; prices can include or exclude it.
5. Service charge, then cash rounding to the configured step, with the
   difference kept as its own figure and posted to its own account.
6. Tenders. Change comes only from cash; overpaying by card leaves a credit.

### How a purchase is costed

Supplier discounts reduce the cost of the goods; freight is added to it. Both are
spread over the lines by value, to the last unit. Ten cartons of twelve become
120 sellable pieces, each carrying one hundred-and-twentieth of what those
cartons really cost — the **landed unit cost**, which becomes the item's moving
average and the basis of every future profit figure.

### What a sale posts

```
Dr  Cash / Card / Bank      what the till actually took, change deducted
Dr  Accounts receivable     whatever the customer still owes
Dr  Sales discounts         every discount given, tax excluded
    Cr  Sales revenue       the goods at their undiscounted price
    Cr  Tax payable
    Cr  Service charge
    Cr/Dr Rounding

Dr  Cost of goods sold      what the goods cost us
Dr  Gifts and samples       the cost of anything given away
    Cr  Inventory
```

`flutter test` checks these identities over thousands of randomly generated
carts and purchases: the lines always sum to the invoice, and the entry the
repository is about to post always balances.

---

## Database

25 tables, 13 views, foreign keys on, WAL journaling. The full schema, with the
reasoning behind each table, is in `lib/core/database/migrations/m001_schema.dart`
and summarised in [`docs/DATABASE.md`](docs/DATABASE.md).

Highlights:

- `journal_entries` / `journal_lines` — real double entry. `v_unbalanced_entries`
  should always be empty; if it is not, something wrote around the `Journal`
  class.
- `stock_moves` — every movement, signed, with the cost it moved at and the
  balance it left behind. `items.stock_qty_milli` is a cache kept by triggers.
- `item_units` — an item's price list, one row per unit, each with its own
  barcode. Buying by the carton and selling by the piece is the normal case,
  not a special one.
- `accounts.system_key` — how the code finds an account. Rename or re-code
  anything in the chart and every posting still lands correctly.
- `parties` — customers, suppliers and employees in one table, each with a real
  sub-account under receivables or payables, created on demand.

---

## What is not in this phase

Sales returns and purchase returns (the tables and the costing rules are in
place, the screens are not), the financial statement screens (trial balance,
income statement, balance sheet — the views exist), journal vouchers, and the
direct ESC/POS and Sunmi transports (printing currently renders the same
receipt and sends it through the system printer or the preview).
#   p o s _ s y s t e m  
 