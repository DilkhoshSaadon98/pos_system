# Database

SQLite, 25 tables and 13 views. Foreign keys are enforced, journaling is WAL.

Conventions:

- `_minor` — money as a whole number of minor units (1/100 of the currency).
- `_milli` — a quantity in thousandths of a unit.
- `_bp` — a percentage in basis points (750 = 7.5 %).
- Dates are ISO-8601 local-time strings, so text ordering is time ordering.

---

## Tables

### `accounts`

Chart of accounts. `system_key` is how code finds an account; `normal_side` drives every balance calculation.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `code` | TEXT | required |
| `name` | TEXT | required |
| `name_ar` | TEXT |  |
| `name_ku` | TEXT |  |
| `type` | TEXT | required |
| `normal_side` | TEXT | required |
| `parent_id` | INTEGER | → `accounts.id` |
| `system_key` | TEXT |  |
| `is_group` | INTEGER | required, default `0` |
| `is_active` | INTEGER | required, default `1` |
| `note` | TEXT |  |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_accounts_parent`, `ux_accounts_system_key`, `ux_accounts_code`

### `app_meta`

Schema version and housekeeping.

| Column | Type | Notes |
| --- | --- | --- |
| `key` | TEXT | primary key |
| `value` | TEXT | required |

### `audit_log`

Who did what.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `happened_at` | TEXT | required |
| `user_id` | INTEGER | → `users.id` |
| `action` | TEXT | required |
| `entity` | TEXT | required |
| `entity_id` | INTEGER |  |
| `detail` | TEXT |  |

Indexes: `ix_audit_when`

### `cart_lines`

Lines of a held sale.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `cart_id` | INTEGER | required, → `carts.id` |
| `item_id` | INTEGER | required, → `items.id` |
| `item_unit_id` | INTEGER | → `item_units.id` |
| `qty_milli` | INTEGER | required, default `1000` |
| `unit_price_minor` | INTEGER | required, default `0` |
| `discount_kind` | TEXT | required, default `'none'` |
| `discount_value` | INTEGER | required, default `0` |
| `is_gift` | INTEGER | required, default `0` |
| `note` | TEXT |  |
| `sort_order` | INTEGER | required, default `0` |
| `created_at` | TEXT | required |

Indexes: `ux_cart_lines_item`, `ix_cart_lines_cart`

### `carts`

Held sales, so a parked cart survives a power cut.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `slot_no` | INTEGER | required |
| `label` | TEXT |  |
| `party_id` | INTEGER | → `parties.id` |
| `price_mode` | TEXT | required, default `'retail'` |
| `status` | TEXT | required, default `'open'` |
| `discount_kind` | TEXT | required, default `'none'` |
| `discount_value` | INTEGER | required, default `0` |
| `tax_rate_bp` | INTEGER | required, default `0` |
| `service_charge_minor` | INTEGER | required, default `0` |
| `note` | TEXT |  |
| `user_id` | INTEGER | → `users.id` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ux_carts_slot`

### `categories`

Item groups.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `name` | TEXT | required |
| `name_ar` | TEXT |  |
| `name_ku` | TEXT |  |
| `parent_id` | INTEGER | → `categories.id` |
| `image_path` | TEXT |  |
| `color` | TEXT |  |
| `sort_order` | INTEGER | required, default `0` |
| `is_active` | INTEGER | required, default `1` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_categories_parent`

### `counters`

Document numbering, allocated inside the caller’s transaction.

| Column | Type | Notes |
| --- | --- | --- |
| `name` | TEXT | primary key |
| `prefix` | TEXT | required, default `''` |
| `period` | TEXT | required, default `''` |
| `last_value` | INTEGER | required, default `0` |

### `item_units`

An item’s price list: one row per unit, with its own barcode and factor to the base unit.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `item_id` | INTEGER | required, → `items.id` |
| `unit_id` | INTEGER | required, → `units.id` |
| `factor_milli` | INTEGER | required |
| `sell_price_minor` | INTEGER | required, default `0` |
| `wholesale_price_minor` | INTEGER | required, default `0` |
| `min_price_minor` | INTEGER | required, default `0` |
| `barcode` | TEXT |  |
| `is_base` | INTEGER | required, default `0` |
| `is_default_sale` | INTEGER | required, default `0` |
| `is_default_purchase` | INTEGER | required, default `0` |
| `sort_order` | INTEGER | required, default `0` |

Indexes: `ix_item_units_item`, `ux_item_units_barcode`, `ux_item_units`

### `items`

Products. `stock_qty_milli` and `avg_cost_minor` are maintained by the stock service and its triggers, never by a screen.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `sku` | TEXT |  |
| `name` | TEXT | required |
| `name_ar` | TEXT |  |
| `name_ku` | TEXT |  |
| `category_id` | INTEGER | → `categories.id` |
| `base_unit_id` | INTEGER | required, → `units.id` |
| `description` | TEXT |  |
| `image_path` | TEXT |  |
| `track_stock` | INTEGER | required, default `1` |
| `is_service` | INTEGER | required, default `0` |
| `allow_negative` | INTEGER | required, default `0` |
| `avg_cost_minor` | INTEGER | required, default `0` |
| `last_cost_minor` | INTEGER | required, default `0` |
| `stock_qty_milli` | INTEGER | required, default `0` |
| `reorder_level_milli` | INTEGER | required, default `0` |
| `tax_rate_bp` | INTEGER | required, default `0` |
| `production_date` | TEXT |  |
| `expiry_date` | TEXT |  |
| `is_active` | INTEGER | required, default `1` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_items_name`, `ix_items_category`, `ux_items_sku`

### `journal_entries`

One financial event. Never deleted — an undo is a reversing entry.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `entry_no` | TEXT | required |
| `entry_date` | TEXT | required |
| `posted_at` | TEXT | required |
| `source_type` | TEXT | required |
| `source_id` | INTEGER |  |
| `memo` | TEXT |  |
| `user_id` | INTEGER | → `users.id` |
| `is_void` | INTEGER | required, default `0` |
| `reversal_of_id` | INTEGER | → `journal_entries.id` |

Indexes: `ix_journal_source`, `ix_journal_date`, `ux_journal_entry_no`

### `journal_lines`

The debits and credits. Refused unless they balance.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `entry_id` | INTEGER | required, → `journal_entries.id` |
| `account_id` | INTEGER | required, → `accounts.id` |
| `party_id` | INTEGER | → `parties.id` |
| `debit_minor` | INTEGER | required, default `0` |
| `credit_minor` | INTEGER | required, default `0` |
| `memo` | TEXT |  |
| `line_no` | INTEGER | required, default `0` |

Indexes: `ix_journal_lines_party`, `ix_journal_lines_account`, `ix_journal_lines_entry`

### `parties`

Customers, suppliers and employees. `account_id` links to their own ledger account under receivables or payables.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `code` | TEXT |  |
| `name` | TEXT | required |
| `kind` | TEXT | required |
| `phone` | TEXT |  |
| `phone2` | TEXT |  |
| `email` | TEXT |  |
| `address` | TEXT |  |
| `note` | TEXT |  |
| `account_id` | INTEGER | → `accounts.id` |
| `credit_limit_minor` | INTEGER | required, default `0` |
| `is_active` | INTEGER | required, default `1` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_parties_account`, `ix_parties_name`, `ix_parties_kind`, `ux_parties_code`

### `payment_allocations`

Which invoices a payment settled.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `payment_id` | INTEGER | required, → `payments.id` |
| `doc_type` | TEXT | required |
| `doc_id` | INTEGER | required |
| `amount_minor` | INTEGER | required |

Indexes: `ix_payment_alloc_doc`, `ix_payment_alloc_payment`

### `payments`

Money received from a customer or paid to a supplier, outside a sale.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `payment_no` | TEXT | required |
| `kind` | TEXT | required |
| `party_id` | INTEGER | → `parties.id` |
| `paid_at` | TEXT | required |
| `method` | TEXT | required, default `'cash'` |
| `account_id` | INTEGER | required, → `accounts.id` |
| `counter_account_id` | INTEGER | → `accounts.id` |
| `amount_minor` | INTEGER | required |
| `discount_minor` | INTEGER | required, default `0` |
| `user_id` | INTEGER | → `users.id` |
| `journal_entry_id` | INTEGER | → `journal_entries.id` |
| `reference` | TEXT |  |
| `note` | TEXT |  |
| `is_void` | INTEGER | required, default `0` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_payments_party`, `ux_payments_no`

### `printer_profiles`

A printer and how a receipt should look on it.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `name` | TEXT | required |
| `driver` | TEXT | required |
| `paper` | TEXT | required, default `'roll80'` |
| `address` | TEXT |  |
| `copies` | INTEGER | required, default `1` |
| `header_text` | TEXT |  |
| `footer_text` | TEXT |  |
| `logo_path` | TEXT |  |
| `show_logo` | INTEGER | required, default `1` |
| `show_barcode` | INTEGER | required, default `1` |
| `show_tax_lines` | INTEGER | required, default `1` |
| `open_drawer` | INTEGER | required, default `0` |
| `auto_print` | INTEGER | required, default `1` |
| `font_scale_bp` | INTEGER | required, default `10000` |
| `is_default` | INTEGER | required, default `0` |
| `is_active` | INTEGER | required, default `1` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

### `purchase_invoice_lines`

What was bought, with the landed cost per base unit that becomes the moving average.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `invoice_id` | INTEGER | required, → `purchase_invoices.id` |
| `item_id` | INTEGER | required, → `items.id` |
| `item_unit_id` | INTEGER | → `item_units.id` |
| `unit_name` | TEXT | required, default `''` |
| `factor_milli` | INTEGER | required, default `1000` |
| `qty_milli` | INTEGER | required |
| `qty_base_milli` | INTEGER | required |
| `unit_cost_minor` | INTEGER | required, default `0` |
| `gross_minor` | INTEGER | required, default `0` |
| `line_discount_minor` | INTEGER | required, default `0` |
| `alloc_discount_minor` | INTEGER | required, default `0` |
| `alloc_fee_minor` | INTEGER | required, default `0` |
| `net_minor` | INTEGER | required, default `0` |
| `landed_total_minor` | INTEGER | required, default `0` |
| `landed_unit_cost_minor` | INTEGER | required, default `0` |
| `tax_rate_bp` | INTEGER | required, default `0` |
| `tax_minor` | INTEGER | required, default `0` |
| `new_sell_price_minor` | INTEGER |  |
| `returned_qty_milli` | INTEGER | required, default `0` |
| `note` | TEXT |  |
| `line_no` | INTEGER | required, default `0` |

Indexes: `ix_purchase_lines_item`, `ix_purchase_lines_invoice`

### `purchase_invoices`

Purchase and purchase-return headers.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `invoice_no` | TEXT | required |
| `doc_type` | TEXT | required, default `'purchase'` |
| `party_id` | INTEGER | → `parties.id` |
| `supplier_ref` | TEXT |  |
| `issued_at` | TEXT | required |
| `user_id` | INTEGER | → `users.id` |
| `gross_minor` | INTEGER | required, default `0` |
| `line_discount_minor` | INTEGER | required, default `0` |
| `invoice_discount_minor` | INTEGER | required, default `0` |
| `discount_total_minor` | INTEGER | required, default `0` |
| `fees_minor` | INTEGER | required, default `0` |
| `subtotal_minor` | INTEGER | required, default `0` |
| `tax_minor` | INTEGER | required, default `0` |
| `rounding_minor` | INTEGER | required, default `0` |
| `total_minor` | INTEGER | required, default `0` |
| `paid_minor` | INTEGER | required, default `0` |
| `due_minor` | INTEGER | required, default `0` |
| `items_count` | INTEGER | required, default `0` |
| `status` | TEXT | required, default `'posted'` |
| `return_of_id` | INTEGER | → `purchase_invoices.id` |
| `journal_entry_id` | INTEGER | → `journal_entries.id` |
| `note` | TEXT |  |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_purchase_party`, `ix_purchase_issued`, `ux_purchase_invoice_no`

### `sale_tenders`

How a sale was paid — one row per method, so split payments are ordinary.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `invoice_id` | INTEGER | required, → `sales_invoices.id` |
| `method` | TEXT | required |
| `account_id` | INTEGER | → `accounts.id` |
| `amount_minor` | INTEGER | required, default `0` |
| `reference` | TEXT |  |

Indexes: `ix_sale_tenders_invoice`

### `sales_invoice_lines`

What was sold, at what price, with its share of the invoice discount and its cost.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `invoice_id` | INTEGER | required, → `sales_invoices.id` |
| `item_id` | INTEGER | required, → `items.id` |
| `item_unit_id` | INTEGER | → `item_units.id` |
| `unit_name` | TEXT | required, default `''` |
| `factor_milli` | INTEGER | required, default `1000` |
| `qty_milli` | INTEGER | required |
| `qty_base_milli` | INTEGER | required |
| `unit_price_minor` | INTEGER | required, default `0` |
| `gross_minor` | INTEGER | required, default `0` |
| `line_discount_minor` | INTEGER | required, default `0` |
| `alloc_discount_minor` | INTEGER | required, default `0` |
| `net_minor` | INTEGER | required, default `0` |
| `tax_rate_bp` | INTEGER | required, default `0` |
| `tax_minor` | INTEGER | required, default `0` |
| `total_minor` | INTEGER | required, default `0` |
| `unit_cost_minor` | INTEGER | required, default `0` |
| `cost_minor` | INTEGER | required, default `0` |
| `is_gift` | INTEGER | required, default `0` |
| `returned_qty_milli` | INTEGER | required, default `0` |
| `note` | TEXT |  |
| `line_no` | INTEGER | required, default `0` |

Indexes: `ix_sales_lines_item`, `ix_sales_lines_invoice`

### `sales_invoices`

Sale and sale-return headers, with every figure the calculator produced.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `invoice_no` | TEXT | required |
| `doc_type` | TEXT | required, default `'sale'` |
| `party_id` | INTEGER | → `parties.id` |
| `issued_at` | TEXT | required |
| `user_id` | INTEGER | → `users.id` |
| `price_mode` | TEXT | required, default `'retail'` |
| `gross_minor` | INTEGER | required, default `0` |
| `line_discount_minor` | INTEGER | required, default `0` |
| `invoice_discount_minor` | INTEGER | required, default `0` |
| `discount_total_minor` | INTEGER | required, default `0` |
| `subtotal_minor` | INTEGER | required, default `0` |
| `tax_minor` | INTEGER | required, default `0` |
| `service_charge_minor` | INTEGER | required, default `0` |
| `rounding_minor` | INTEGER | required, default `0` |
| `total_minor` | INTEGER | required, default `0` |
| `paid_minor` | INTEGER | required, default `0` |
| `change_minor` | INTEGER | required, default `0` |
| `due_minor` | INTEGER | required, default `0` |
| `cost_minor` | INTEGER | required, default `0` |
| `profit_minor` | INTEGER | required, default `0` |
| `items_count` | INTEGER | required, default `0` |
| `status` | TEXT | required, default `'posted'` |
| `return_of_id` | INTEGER | → `sales_invoices.id` |
| `journal_entry_id` | INTEGER | → `journal_entries.id` |
| `note` | TEXT |  |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ix_sales_status`, `ix_sales_party`, `ix_sales_issued`, `ux_sales_invoice_no`

### `settings`

Key/value shop settings.

| Column | Type | Notes |
| --- | --- | --- |
| `key` | TEXT | primary key |
| `value` | TEXT |  |
| `updated_at` | TEXT | required |

### `stock_moves`

The stock ledger. Signed quantities in base units, with the cost each movement carried.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `item_id` | INTEGER | required, → `items.id` |
| `moved_at` | TEXT | required |
| `kind` | TEXT | required |
| `qty_milli` | INTEGER | required |
| `unit_cost_minor` | INTEGER | required, default `0` |
| `cost_total_minor` | INTEGER | required, default `0` |
| `balance_after_milli` | INTEGER | required, default `0` |
| `doc_type` | TEXT |  |
| `doc_id` | INTEGER |  |
| `doc_line_id` | INTEGER |  |
| `user_id` | INTEGER | → `users.id` |
| `note` | TEXT |  |

Indexes: `ix_stock_moves_date`, `ix_stock_moves_doc`, `ix_stock_moves_item`

### `units`

Units of measure available to items.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `name` | TEXT | required |
| `name_ar` | TEXT |  |
| `name_ku` | TEXT |  |
| `symbol` | TEXT |  |
| `allow_fraction` | INTEGER | required, default `0` |
| `is_active` | INTEGER | required, default `1` |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ux_units_name`

### `users`

Local logins, salted and stretched.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER | primary key |
| `full_name` | TEXT | required |
| `username` | TEXT | required |
| `password_hash` | TEXT | required |
| `password_salt` | TEXT | required |
| `role` | TEXT | required |
| `phone` | TEXT |  |
| `is_active` | INTEGER | required, default `1` |
| `last_login_at` | TEXT |  |
| `created_at` | TEXT | required |
| `updated_at` | TEXT | required |

Indexes: `ux_users_username`

---

## Views

### `v_account_balances`

Every account with its debits, credits and balance, signed by its normal side.

Columns: `account_id`, `code`, `name`, `type`, `normal_side`, `parent_id`, `system_key`, `debit_minor`, `credit_minor`, `balance_minor`

### `v_balance_sheet`

Assets, liabilities and equity with their balances.

Columns: `type`, `code`, `name`, `system_key`, `balance_minor`

### `v_daily_sales`

Takings, cost, profit, discount and tax by day.

Columns: `day`, `invoice_count`, `total_minor`, `cost_minor`, `profit_minor`, `discount_minor`, `tax_minor`

### `v_general_ledger`

Every posting, with its account, party and user.

Columns: `line_id`, `entry_id`, `entry_no`, `entry_date`, `posted_at`, `source_type`, `source_id`, `entry_memo`, `line_memo`, `account_id`, `account_code`, `account_name`, `account_type`, `party_id`, `party_name`, `debit_minor`, `credit_minor`, `user_name`

### `v_income_statement`

Revenue and expense accounts, signed for reading.

Columns: `type`, `code`, `name`, `system_key`, `amount_minor`

### `v_inventory_movements`

The stock ledger, readable.

Columns: `id`, `moved_at`, `kind`, `item_id`, `item_name`, `base_unit_name`, `qty_milli`, `unit_cost_minor`, `cost_total_minor`, `balance_after_milli`, `doc_type`, `doc_id`, `note`

### `v_item_stock_summary`

Purchased, sold, returned and remaining, per item.

Columns: `item_id`, `name`, `stock_qty_milli`, `avg_cost_minor`, `stock_value_minor`, `in_qty_milli`, `sold_qty_milli`, `sale_return_qty_milli`, `purchase_return_qty_milli`, `adjust_qty_milli`

### `v_items_full`

Items with their category, base unit, default price, primary barcode and stock value.

Columns: `id`, `sku`, `name`, `name_ar`, `name_ku`, `category_id`, `base_unit_id`, `description`, `image_path`, `track_stock`, `is_service`, `allow_negative`, `avg_cost_minor`, `last_cost_minor`, `stock_qty_milli`, `reorder_level_milli`, `tax_rate_bp`, `production_date`, `expiry_date`, `is_active`, `created_at`, `updated_at`, `category_name`, `base_unit_name`, `default_sell_price_minor`, `primary_barcode`, `unit_count`, `stock_value_minor`

### `v_party_balances`

What each customer or supplier owes, straight from the ledger.

Columns: `party_id`, `name`, `kind`, `phone`, `account_id`, `account_code`, `debit_minor`, `credit_minor`, `balance_minor`

### `v_purchase_invoices_full`

Purchases with the supplier name.

Columns: `id`, `invoice_no`, `doc_type`, `party_id`, `supplier_ref`, `issued_at`, `user_id`, `gross_minor`, `line_discount_minor`, `invoice_discount_minor`, `discount_total_minor`, `fees_minor`, `subtotal_minor`, `tax_minor`, `rounding_minor`, `total_minor`, `paid_minor`, `due_minor`, `items_count`, `status`, `return_of_id`, `journal_entry_id`, `note`, `created_at`, `updated_at`, `party_name`, `party_phone`, `user_name`

### `v_sales_invoices_full`

Invoices with the customer and cashier names.

Columns: `id`, `invoice_no`, `doc_type`, `party_id`, `issued_at`, `user_id`, `price_mode`, `gross_minor`, `line_discount_minor`, `invoice_discount_minor`, `discount_total_minor`, `subtotal_minor`, `tax_minor`, `service_charge_minor`, `rounding_minor`, `total_minor`, `paid_minor`, `change_minor`, `due_minor`, `cost_minor`, `profit_minor`, `items_count`, `status`, `return_of_id`, `journal_entry_id`, `note`, `created_at`, `updated_at`, `party_name`, `party_phone`, `cashier_name`

### `v_trial_balance`

The trial balance. Debit and credit columns must total the same.

Columns: `account_id`, `code`, `name`, `type`, `normal_side`, `debit_minor`, `credit_minor`, `debit_balance_minor`, `credit_balance_minor`

### `v_unbalanced_entries`

Should always be empty. Anything here was written around the Journal class.

Columns: `entry_id`, `entry_no`, `entry_date`, `debit_minor`, `credit_minor`, `difference_minor`
