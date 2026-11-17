import '../../../../core/accounting/account_keys.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardLocalDataSource {
  DashboardLocalDataSource(this._database);

  final AppDatabase _database;

  Future<DashboardSnapshot> load({DateTime? day}) async {
    final DateTime when = day ?? DateTime.now();
    final String from = Time.startOfDay(when);
    final String to = Time.endOfDay(when);

    //? get sales invoices:
    final List<Map<String, Object?>> sales = await _database.db.rawQuery(
      '''
      SELECT IFNULL(SUM(CASE WHEN doc_type = 'sale' THEN total_minor  ELSE -total_minor  END), 0) AS total,
             IFNULL(SUM(CASE WHEN doc_type = 'sale' THEN profit_minor ELSE -profit_minor END), 0) AS profit,
             IFNULL(SUM(CASE WHEN doc_type = 'sale' THEN due_minor    ELSE 0 END), 0)             AS credit,
             COUNT(*) AS invoices
        FROM sales_invoices
       WHERE status <> 'void' AND issued_at BETWEEN ? AND ?
      ''',
      <Object?>[from, to],
    );

    //? get account balances:
    final List<Map<String, Object?>> balances = await _database.db.rawQuery(
      '''
      SELECT system_key, balance_minor FROM v_account_balances
       WHERE system_key IN (?, ?, ?, ?, ?)
      ''',
      <Object?>[
        AccountKeys.cash,
        AccountKeys.bank,
        AccountKeys.inventory,
        AccountKeys.receivable,
        AccountKeys.payable,
      ],
    );
    final Map<String, int> byKey = <String, int>{
      for (final Map<String, Object?> r in balances)
        '${r['system_key']}': r['balance_minor'] as int? ?? 0,
    };
  //? get accounts:
    final List<Map<String, Object?>> subtotals = await _database.db.rawQuery(
      '''
      SELECT parent.system_key AS key,
             IFNULL(SUM(CASE WHEN parent.normal_side = 'debit'
                             THEN l.debit_minor - l.credit_minor
                             ELSE l.credit_minor - l.debit_minor END), 0) AS balance
        FROM accounts a
        JOIN accounts parent ON parent.id = a.parent_id
        LEFT JOIN journal_lines l   ON l.account_id = a.id
        LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
       WHERE parent.system_key IN (?, ?)
       GROUP BY parent.system_key
      ''',
      <Object?>[AccountKeys.receivable, AccountKeys.payable],
    );
    for (final Map<String, Object?> r in subtotals) {
      final String key = '${r['key']}';
      byKey[key] = (byKey[key] ?? 0) + ((r['balance'] as int?) ?? 0);
    }
  //? get items:
    final List<Map<String, Object?>> stock = await _database.db.rawQuery(
      '''
      SELECT IFNULL(SUM(stock_qty_milli * avg_cost_minor / 1000), 0) AS value,
             SUM(CASE WHEN track_stock = 1 AND reorder_level_milli > 0
                       AND stock_qty_milli <= reorder_level_milli THEN 1 ELSE 0 END) AS low,
             SUM(CASE WHEN track_stock = 1 AND stock_qty_milli <= 0 THEN 1 ELSE 0 END) AS out
        FROM items
       WHERE is_active = 1 AND kind = 'stock'
      ''',
    );

    final List<Map<String, Object?>> week = await _database.db.rawQuery(
      '''
      SELECT day, total_minor, profit_minor
        FROM v_daily_sales
       ORDER BY day DESC
       LIMIT 14
      ''',
    );

    final List<Map<String, Object?>> top = await _database.db.rawQuery(
      '''
      SELECT CASE WHEN i.variant_name IS NULL OR i.variant_name = ''
                  THEN i.name
                  ELSE i.name || ' — ' || i.variant_name END AS name,
             SUM(l.qty_base_milli) AS qty,
             SUM(l.total_minor)    AS total
        FROM sales_invoice_lines l
        JOIN sales_invoices s ON s.id = l.invoice_id
        JOIN items i          ON i.id = l.item_id
       WHERE s.status <> 'void' AND s.doc_type = 'sale' AND s.issued_at >= ?
       GROUP BY l.item_id
       ORDER BY total DESC
       LIMIT 8
      ''',
      <Object?>[Time.startOfMonth(when)],
    );

    final List<Map<String, Object?>> lowStock = await _database.db.rawQuery(
      '''
      SELECT id,
             CASE WHEN variant_name IS NULL OR variant_name = ''
                  THEN name ELSE name || ' — ' || variant_name END AS name,
             stock_qty_milli, reorder_level_milli, base_unit_name
        FROM v_items_full
       WHERE is_active = 1 AND track_stock = 1 AND kind = 'stock'
         AND reorder_level_milli > 0
         AND stock_qty_milli <= reorder_level_milli
       ORDER BY stock_qty_milli
       LIMIT 10
      ''',
    );

    final Map<String, Object?> s = sales.first;
    final Map<String, Object?> st = stock.first;

    return DashboardSnapshot(
      day: when,
      salesToday: Money.fromDb(s['total']),
      profitToday: Money.fromDb(s['profit']),
      creditToday: Money.fromDb(s['credit']),
      invoicesToday: s['invoices'] as int? ?? 0,
      cash: Money(byKey[AccountKeys.cash] ?? 0),
      bank: Money(byKey[AccountKeys.bank] ?? 0),
      receivable: Money(byKey[AccountKeys.receivable] ?? 0),
      payable: Money(byKey[AccountKeys.payable] ?? 0),
      inventoryAccount: Money(byKey[AccountKeys.inventory] ?? 0),
      stockValue: Money.fromDb(st['value']),
      lowStockCount: st['low'] as int? ?? 0,
      outOfStockCount: st['out'] as int? ?? 0,
      dailySeries: week.reversed
          .map((Map<String, Object?> r) => DailyPoint(
                day: '${r['day']}',
                total: Money.fromDb(r['total_minor']),
                profit: Money.fromDb(r['profit_minor']),
              ))
          .toList(),
      topItems: top
          .map((Map<String, Object?> r) => TopItem(
                name: '${r['name']}',
                qtyMilli: (r['qty'] as num?)?.toInt() ?? 0,
                total: Money.fromDb(r['total']),
              ))
          .toList(),
      lowStock: lowStock
          .map((Map<String, Object?> r) => LowStockItem(
                id: r['id'] as int,
                name: '${r['name']}',
                qtyMilli: r['stock_qty_milli'] as int? ?? 0,
                reorderMilli: r['reorder_level_milli'] as int? ?? 0,
                unitName: '${r['base_unit_name'] ?? ''}',
              ))
          .toList(),
    );
  }
}
