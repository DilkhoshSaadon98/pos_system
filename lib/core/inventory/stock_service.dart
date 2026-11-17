import 'package:sqflite_common/sqlite_api.dart';

import '../calc/costing.dart';
import '../error/exceptions.dart';
import '../utils/time.dart';

/// The only way stock ever moves.
///
/// Nothing else in the app writes `items.stock_qty_milli` or `items.avg_cost_minor`:
/// a receipt or an issue is recorded here as a row in `stock_moves`, the
/// database trigger keeps the cached quantity in step, and the moving average
/// is recalculated in the same breath. That is why the item card, the inventory
/// account and the movement report can never disagree.
class StockService {
  const StockService._();

  /// Goods coming in: a purchase, a customer return, an opening balance or a
  /// positive adjustment. Updates the item's moving-average cost.
  static Future<int> receive(
    DatabaseExecutor db, {
    required int itemId,
    required int qtyBaseMilli,
    required int unitCostMinor,
    required String kind,
    String? docType,
    int? docId,
    int? docLineId,
    int? userId,
    String? movedAt,
    String? note,
    bool updateAverage = true,
    int? batchId,
  }) async {
    if (qtyBaseMilli <= 0) {
      throw const AppFailure.validation('Received quantity must be positive.');
    }
    final _ItemStock stock = await _read(db, itemId);
    if (!stock.trackStock) return 0;

    final int newAvg = updateAverage
        ? Costing.averageAfterReceipt(
            onHandMilli: stock.qtyMilli,
            currentAvgMinor: stock.avgCostMinor,
            receivedMilli: qtyBaseMilli,
            receivedUnitCostMinor: unitCostMinor,
          )
        : stock.avgCostMinor;

    final int moveId = await db.insert('stock_moves', <String, Object?>{
      'item_id': itemId,
      'moved_at': movedAt ?? Time.stamp(),
      'kind': kind,
      'qty_milli': qtyBaseMilli,
      'unit_cost_minor': unitCostMinor,
      'cost_total_minor':
          Costing.stockValue(qtyMilli: qtyBaseMilli, avgCostMinor: unitCostMinor),
      'balance_after_milli': stock.qtyMilli + qtyBaseMilli,
      'doc_type': docType,
      'doc_id': docId,
      'doc_line_id': docLineId,
      'user_id': userId,
      'note': note,
      'batch_id': batchId,
    });

    await db.update(
      'items',
      <String, Object?>{
        'avg_cost_minor': newAvg,
        'last_cost_minor': unitCostMinor,
        'updated_at': Time.stamp(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );

    return moveId;
  }

  /// Goods going out: a sale, a supplier return, waste or a negative
  /// adjustment. Returns the cost of what left, which is what the caller posts
  /// to cost of sales.
  ///
  /// The average cost is **not** touched by an issue — that is the definition
  /// of a moving average, and it is what keeps two sales of the same item at
  /// the same moment costing the same.
  static Future<StockIssue> issue(
    DatabaseExecutor db, {
    required int itemId,
    required int qtyBaseMilli,
    required String kind,
    int? unitCostOverrideMinor,
    String? docType,
    int? docId,
    int? docLineId,
    int? userId,
    String? movedAt,
    String? note,
    bool allowNegativeOverride = false,

    /// Which physical batch this came out of, when the item is counted that
    /// way. The value of the movement is unaffected — cost is still the moving
    /// average — so a shop can turn batch tracking on without a single figure
    /// in the ledger changing.
    int? batchId,
  }) async {
    if (qtyBaseMilli <= 0) {
      throw const AppFailure.validation('Issued quantity must be positive.');
    }
    final _ItemStock stock = await _read(db, itemId);
    if (!stock.trackStock) {
      return const StockIssue(moveId: 0, unitCostMinor: 0, costMinor: 0);
    }

    final int remaining = stock.qtyMilli - qtyBaseMilli;
    if (remaining < 0 && !stock.allowNegative && !allowNegativeOverride) {
      throw AppFailure.validation(
        '"${stock.name}" only has ${(stock.qtyMilli / 1000).toStringAsFixed(3)} '
        'in stock.',
      );
    }

    final int unitCost = unitCostOverrideMinor ?? stock.avgCostMinor;
    final int cost =
        Costing.issueValue(qtyMilli: qtyBaseMilli, avgCostMinor: unitCost);

    final int moveId = await db.insert('stock_moves', <String, Object?>{
      'item_id': itemId,
      'moved_at': movedAt ?? Time.stamp(),
      'kind': kind,
      'qty_milli': -qtyBaseMilli,
      'unit_cost_minor': unitCost,
      'cost_total_minor': -cost,
      'balance_after_milli': remaining,
      'doc_type': docType,
      'doc_id': docId,
      'doc_line_id': docLineId,
      'user_id': userId,
      'note': note,
      'batch_id': batchId,
    });

    return StockIssue(moveId: moveId, unitCostMinor: unitCost, costMinor: cost);
  }

  /// Sets an item's stock to a counted figure. The difference becomes a single
  /// adjustment movement, valued at the current average, so the inventory
  /// account can be corrected by the same amount.
  static Future<StockAdjustment> setCountedQuantity(
    DatabaseExecutor db, {
    required int itemId,
    required int countedBaseMilli,
    int? userId,
    String? note,
  }) async {
    final _ItemStock stock = await _read(db, itemId);
    final int diff = countedBaseMilli - stock.qtyMilli;
    if (diff == 0) {
      return const StockAdjustment(moveId: 0, qtyMilli: 0, valueMinor: 0);
    }

    final int value =
        Costing.stockValue(qtyMilli: diff, avgCostMinor: stock.avgCostMinor);

    final int moveId = await db.insert('stock_moves', <String, Object?>{
      'item_id': itemId,
      'moved_at': Time.stamp(),
      'kind': 'adjustment',
      'qty_milli': diff,
      'unit_cost_minor': stock.avgCostMinor,
      'cost_total_minor': value,
      'balance_after_milli': countedBaseMilli,
      'doc_type': 'adjustment',
      'user_id': userId,
      'note': note,
    });

    return StockAdjustment(moveId: moveId, qtyMilli: diff, valueMinor: value);
  }

  static Future<_ItemStock> _read(DatabaseExecutor db, int itemId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'items',
      columns: <String>[
        'name',
        'stock_qty_milli',
        'avg_cost_minor',
        'track_stock',
        'allow_negative',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AppFailure.notFound('Item $itemId does not exist.');
    }
    final Map<String, Object?> r = rows.first;
    return _ItemStock(
      name: '${r['name']}',
      qtyMilli: r['stock_qty_milli'] as int? ?? 0,
      avgCostMinor: r['avg_cost_minor'] as int? ?? 0,
      trackStock: (r['track_stock'] as int? ?? 1) == 1,
      allowNegative: (r['allow_negative'] as int? ?? 0) == 1,
    );
  }
}

class StockIssue {
  const StockIssue({
    required this.moveId,
    required this.unitCostMinor,
    required this.costMinor,
  });

  final int moveId;
  final int unitCostMinor;
  final int costMinor;
}

class StockAdjustment {
  const StockAdjustment({
    required this.moveId,
    required this.qtyMilli,
    required this.valueMinor,
  });

  final int moveId;
  final int qtyMilli;
  final int valueMinor;
}

class _ItemStock {
  const _ItemStock({
    required this.name,
    required this.qtyMilli,
    required this.avgCostMinor,
    required this.trackStock,
    required this.allowNegative,
  });

  final String name;
  final int qtyMilli;
  final int avgCostMinor;
  final bool trackStock;
  final bool allowNegative;
}
