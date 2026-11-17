import '../../core/classes/enums.dart';
import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import '../../core/money/money.dart';
import '../../core/utils/time.dart';

/// One row of the stock ledger.
class StockMove {
  const StockMove({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.movedAt,
    required this.kind,
    required this.qtyMilli,
    required this.unitCost,
    required this.costTotal,
    required this.balanceAfterMilli,
    required this.unitName,
    this.docType,
    this.docId,
    this.note,
  });

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name'] ?? ''}',
        movedAt: '${m['moved_at']}',
        kind: StockMoveKind.fromDb(m['kind']),
        qtyMilli: m['qty_milli'] as int? ?? 0,
        unitCost: Money.fromDb(m['unit_cost_minor']),
        costTotal: Money.fromDb(m['cost_total_minor']),
        balanceAfterMilli: m['balance_after_milli'] as int? ?? 0,
        unitName: '${m['base_unit_name'] ?? ''}',
        docType: m['doc_type'] as String?,
        docId: m['doc_id'] as int?,
        note: m['note'] as String?,
      );

  final int id;
  final int itemId;
  final String itemName;
  final String movedAt;
  final StockMoveKind kind;

  /// Positive when goods came in, negative when they left. One column, one
  /// sign — the old schema had separate in and out fields and reports that
  /// disagreed about which was which.
  final int qtyMilli;

  final Money unitCost;
  final Money costTotal;
  final int balanceAfterMilli;
  final String unitName;
  final String? docType;
  final int? docId;
  final String? note;

  bool get isIn => qtyMilli > 0;
}

/// The shelf, as the ledger describes it.
abstract class InventoryRepository {
  Future<Result<List<StockMove>>> movements({
    required DateTime from,
    required DateTime to,
    int? itemId,
    StockMoveKind? kind,
    String? search,
    int limit = 500,
  });

  Future<Result<InventoryTotals>> totals();
}

class InventoryTotals {
  const InventoryTotals({
    required this.stockValue,
    required this.itemCount,
    required this.lowCount,
    required this.outCount,
    required this.negativeCount,
  });

  static const InventoryTotals empty = InventoryTotals(
    stockValue: Money.zero,
    itemCount: 0,
    lowCount: 0,
    outCount: 0,
    negativeCount: 0,
  );

  final Money stockValue;
  final int itemCount;
  final int lowCount;
  final int outCount;

  /// Items whose recorded stock is below zero. Possible only where an item
  /// allows it, and always worth counting.
  final int negativeCount;
}

class InventoryLocalDataSource {
  InventoryLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<StockMove>> movements({
    required DateTime from,
    required DateTime to,
    int? itemId,
    StockMoveKind? kind,
    String? search,
    int limit = 500,
  }) async {
    final StringBuffer where = StringBuffer('m.moved_at BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[
      Time.startOfDay(from),
      Time.endOfDay(to),
    ];

    if (itemId != null) {
      where.write(' AND m.item_id = ?');
      args.add(itemId);
    }
    if (kind != null) {
      where.write(' AND m.kind = ?');
      args.add(kind.dbValue);
    }
    final String q = (search ?? '').trim();
    if (q.isNotEmpty) {
      where.write(' AND (i.name LIKE ? OR i.sku LIKE ? OR m.note LIKE ?)');
      args
        ..add('%$q%')
        ..add('%$q%')
        ..add('%$q%');
    }

    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT m.*,
             CASE WHEN i.variant_name IS NULL OR i.variant_name = ''
                  THEN i.name ELSE i.name || ' — ' || i.variant_name END
               AS item_name,
             IFNULL(u.name, '') AS base_unit_name
        FROM stock_moves m
        JOIN items i      ON i.id = m.item_id
        LEFT JOIN units u ON u.id = i.base_unit_id
       WHERE ${where.toString()}
       ORDER BY m.moved_at DESC, m.id DESC
       LIMIT ${limit.clamp(1, 5000)}
      ''',
      args,
    );
    return rows.map(StockMove.fromMap).toList();
  }

  Future<InventoryTotals> totals() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT IFNULL(SUM(stock_qty_milli * avg_cost_minor / 1000), 0) AS value,
             COUNT(*) AS items,
             SUM(CASE WHEN reorder_level_milli > 0
                       AND stock_qty_milli <= reorder_level_milli
                      THEN 1 ELSE 0 END) AS low,
             SUM(CASE WHEN stock_qty_milli = 0 THEN 1 ELSE 0 END) AS out,
             SUM(CASE WHEN stock_qty_milli < 0 THEN 1 ELSE 0 END) AS negative
        FROM items
       WHERE is_active = 1 AND track_stock = 1 AND kind = 'stock'
      ''',
    );
    final Map<String, Object?> r = rows.first;

    return InventoryTotals(
      stockValue: Money.fromDb(r['value']),
      itemCount: r['items'] as int? ?? 0,
      lowCount: (r['low'] as num?)?.toInt() ?? 0,
      outCount: (r['out'] as num?)?.toInt() ?? 0,
      negativeCount: (r['negative'] as num?)?.toInt() ?? 0,
    );
  }
}

class InventoryRepositoryImpl implements InventoryRepository {
  const InventoryRepositoryImpl(this._local);

  final InventoryLocalDataSource _local;

  @override
  Future<Result<List<StockMove>>> movements({
    required DateTime from,
    required DateTime to,
    int? itemId,
    StockMoveKind? kind,
    String? search,
    int limit = 500,
  }) =>
      guard(() => _local.movements(
            from: from,
            to: to,
            itemId: itemId,
            kind: kind,
            search: search,
            limit: limit,
          ));

  @override
  Future<Result<InventoryTotals>> totals() => guard(_local.totals);
}

void initInventoryInjection() {
  sl.registerLazySingleton<InventoryLocalDataSource>(
    () => InventoryLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<InventoryRepository>(
    () => InventoryRepositoryImpl(sl<InventoryLocalDataSource>()),
  );
}
