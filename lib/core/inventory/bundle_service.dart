import 'package:sqflite_common/sqlite_api.dart';

import '../money/arithmetic.dart';
import 'stock_service.dart';

/// One part of a bundle, resolved into base units.
class BundleComponent {
  const BundleComponent({
    required this.itemId,
    required this.name,
    required this.qtyBaseMilli,
    required this.avgCostMinor,
    required this.trackStock,
    required this.onHandMilli,
    this.unitName = '',
  });

  final int itemId;
  final String name;

  /// How many **base** units of the component one bundle contains, ×1000.
  final int qtyBaseMilli;

  final int avgCostMinor;
  final bool trackStock;
  final int onHandMilli;
  final String unitName;

  /// What one bundle's worth of this part currently costs.
  int get costPerBundleMinor =>
      mulDivRound(avgCostMinor, qtyBaseMilli, 1000);

  /// How many whole bundles the stock on hand could build.
  int get buildableBundles {
    if (!trackStock) return 1 << 30;
    if (qtyBaseMilli <= 0) return 0;
    return onHandMilli ~/ qtyBaseMilli;
  }
}

/// What a bundle is made of, and what happens when one is sold.
///
/// A bundle is one line on the invoice and several movements in the stock
/// ledger. Keeping it that way is the whole point: the customer bought a
/// "family meal", but the shelf lost two burgers, two drinks and a portion of
/// chips, each leaving at its own moving-average cost. Costing a bundle as a
/// single made-up figure — which is what a shop does when the software cannot
/// do this — is how a menu ends up looking profitable while the kitchen loses
/// money.
///
/// Nesting is refused by the schema, so this never has to recurse.
class BundleService {
  const BundleService._();

  /// Reads a bundle's parts with their current cost and stock.
  static Future<List<BundleComponent>> componentsOf(
    DatabaseExecutor db,
    int bundleItemId,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT b.qty_milli,
             b.component_item_id,
             i.name,
             i.avg_cost_minor,
             i.track_stock,
             i.stock_qty_milli,
             IFNULL(iu.factor_milli, 1000) AS factor_milli,
             IFNULL(u.name, '')            AS unit_name
        FROM item_bundle_components b
        JOIN items i            ON i.id = b.component_item_id
        LEFT JOIN item_units iu ON iu.id = b.item_unit_id
        LEFT JOIN units u       ON u.id = iu.unit_id
       WHERE b.bundle_item_id = ?
       ORDER BY b.sort_order, b.id
      ''',
      <Object?>[bundleItemId],
    );

    return rows.map((Map<String, Object?> r) {
      final int qty = r['qty_milli'] as int? ?? 0;
      final int factor = r['factor_milli'] as int? ?? 1000;
      return BundleComponent(
        itemId: r['component_item_id'] as int,
        name: '${r['name']}',
        qtyBaseMilli: mulDivRound(qty, factor, 1000),
        avgCostMinor: r['avg_cost_minor'] as int? ?? 0,
        trackStock: (r['track_stock'] as int? ?? 1) == 1,
        onHandMilli: r['stock_qty_milli'] as int? ?? 0,
        unitName: '${r['unit_name']}',
      );
    }).toList(growable: false);
  }

  /// What one bundle costs at today's averages.
  ///
  /// Read straight out of `v_bundle_costs` when only the number is wanted, so
  /// the till can show a profit figure per line without four extra queries.
  static Future<int> costOf(DatabaseExecutor db, int bundleItemId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'v_bundle_costs',
      columns: <String>['cost_minor'],
      where: 'item_id = ?',
      whereArgs: <Object?>[bundleItemId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['cost_minor'] as num?)?.toInt() ?? 0;
  }

  /// Takes the parts of [qtyBundlesMilli] bundles out of stock and returns what
  /// they actually cost.
  ///
  /// The figure that comes back — not the estimate the till showed — is what
  /// gets written on the invoice line and posted to cost of sales, because
  /// between putting a bundle in the cart and taking the money a delivery may
  /// have moved the average.
  static Future<int> issueFor(
    DatabaseExecutor db, {
    required int bundleItemId,
    required int qtyBundlesMilli,
    required String kind,
    String? docType,
    int? docId,
    int? docLineId,
    int? userId,
    String? movedAt,
    String? note,
    bool allowNegativeOverride = false,
  }) async {
    final List<BundleComponent> parts = await componentsOf(db, bundleItemId);
    int cost = 0;

    for (final BundleComponent part in parts) {
      final int qty = mulDivRound(part.qtyBaseMilli, qtyBundlesMilli, 1000);
      if (qty <= 0) continue;

      final StockIssue issue = await StockService.issue(
        db,
        itemId: part.itemId,
        qtyBaseMilli: qty,
        kind: kind,
        docType: docType,
        docId: docId,
        docLineId: docLineId,
        userId: userId,
        movedAt: movedAt,
        note: note,
        allowNegativeOverride: allowNegativeOverride,
      );
      cost += issue.costMinor;
    }

    return cost;
  }

  /// Puts the parts of a returned bundle back, at the cost the return line
  /// carries, so gross profit stays symmetrical.
  static Future<int> receiveFor(
    DatabaseExecutor db, {
    required int bundleItemId,
    required int qtyBundlesMilli,
    required String kind,
    String? docType,
    int? docId,
    int? docLineId,
    int? userId,
    String? movedAt,
    String? note,
  }) async {
    final List<BundleComponent> parts = await componentsOf(db, bundleItemId);
    int cost = 0;

    for (final BundleComponent part in parts) {
      final int qty = mulDivRound(part.qtyBaseMilli, qtyBundlesMilli, 1000);
      if (qty <= 0) continue;

      await StockService.receive(
        db,
        itemId: part.itemId,
        qtyBaseMilli: qty,
        unitCostMinor: part.avgCostMinor,
        kind: kind,
        docType: docType,
        docId: docId,
        docLineId: docLineId,
        userId: userId,
        movedAt: movedAt,
        note: note,
        // Goods coming back in at the average they left at must not move that
        // average — otherwise a return would quietly re-price the shelf.
        updateAverage: false,
      );
      cost += mulDivRound(part.avgCostMinor, qty, 1000);
    }

    return cost;
  }
}
