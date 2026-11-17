import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import '../../core/money/money.dart';

/// One product, seen from the angle a shopkeeper asks about.
class ItemInsight {
  const ItemInsight({
    required this.itemId,
    required this.name,
    required this.stockMilli,
    required this.stockValue,
    required this.revenue30d,
    required this.profit30d,
    required this.sold30dMilli,
    required this.reorderLevelMilli,
    this.sku,
    this.categoryName,
    this.lastSoldAt,
  });

  factory ItemInsight.fromRow(Map<String, Object?> m) => ItemInsight(
        itemId: m['item_id'] as int,
        name: '${m['item_name']}',
        sku: m['sku'] as String?,
        categoryName: m['category_name'] as String?,
        stockMilli: m['stock_qty_milli'] as int? ?? 0,
        stockValue: Money.fromDb(m['stock_value_minor']),
        revenue30d: Money.fromDb(m['revenue_30d_minor']),
        profit30d: Money.fromDb(m['profit_30d_minor']),
        sold30dMilli: m['sold_30d_milli'] as int? ?? 0,
        reorderLevelMilli: m['reorder_level_milli'] as int? ?? 0,
        lastSoldAt: m['last_sold_at'] as String?,
      );

  final int itemId;
  final String name;
  final String? sku;
  final String? categoryName;

  final int stockMilli;

  /// What is sitting on the shelf, at cost. This is the number that makes dead
  /// stock hurt: it is money the shop has already spent.
  final Money stockValue;

  final Money revenue30d;
  final Money profit30d;
  final int sold30dMilli;
  final int reorderLevelMilli;

  /// Null when it has never been sold at all — which is its own answer.
  final String? lastSoldAt;

  /// Days since the last sale, or null when there has never been one.
  int? get daysSinceSold {
    if (lastSoldAt == null) return null;
    final DateTime? then = DateTime.tryParse(lastSoldAt!);
    if (then == null) return null;
    return DateTime.now().difference(then).inDays;
  }

  /// Margin on what it sold in the last month, in basis points.
  int get marginBp => revenue30d.minor == 0
      ? 0
      : (profit30d.minor * 10000) ~/ revenue30d.minor;

  /// Roughly how long the shelf will last at the last month's rate. Null when
  /// nothing is moving, because "for ever" is not a number.
  int? get daysOfCover {
    if (sold30dMilli <= 0) return null;
    return (stockMilli * 30) ~/ sold30dMilli;
  }

  bool get needsReorder =>
      reorderLevelMilli > 0 && stockMilli <= reorderLevelMilli;
}

/// An hour of the trading day.
class HourOfDay {
  const HourOfDay({
    required this.hour,
    required this.salesCount,
    required this.total,
    required this.profit,
  });

  factory HourOfDay.fromRow(Map<String, Object?> m) => HourOfDay(
        hour: m['hour_of_day'] as int? ?? 0,
        salesCount: m['sales_count'] as int? ?? 0,
        total: Money.fromDb(m['total_minor']),
        profit: Money.fromDb(m['profit_minor']),
      );

  final int hour;
  final int salesCount;
  final Money total;
  final Money profit;
}

/// Everything the insights screen shows, gathered once.
class InsightsSnapshot {
  const InsightsSnapshot({
    required this.deadStock,
    required this.bestSellers,
    required this.bestMargins,
    required this.needsReorder,
    required this.hours,
    required this.deadStockValue,
    required this.stockValue,
  });

  /// Nothing sold for a long time, worst first — by what it is worth, not by
  /// how long, because a dusty box of cheap sweets is not the problem.
  final List<ItemInsight> deadStock;

  final List<ItemInsight> bestSellers;
  final List<ItemInsight> bestMargins;
  final List<ItemInsight> needsReorder;
  final List<HourOfDay> hours;

  final Money deadStockValue;
  final Money stockValue;

  /// The share of the shop's money that is not moving, in basis points.
  int get deadShareBp => stockValue.minor == 0
      ? 0
      : (deadStockValue.minor * 10000) ~/ stockValue.minor;

  HourOfDay? get busiestHour {
    if (hours.isEmpty) return null;
    return hours.reduce((HourOfDay a, HourOfDay b) =>
        b.salesCount > a.salesCount ? b : a);
  }
}

/// The questions a shopkeeper actually asks at the end of a month.
///
/// Not a dashboard of everything measurable — four questions with answers a
/// person can act on the same afternoon:
///
/// * **What is not selling?** Money already spent, sitting on a shelf.
/// * **What earns the most?** Not what sells the most: a fast seller at 2 %
///   can be worth less than a slow one at 40 %.
/// * **When is the shop busy?** Which is when to put a second person on.
/// * **What do I need to buy?** Below its level, with what it sells in a month.
class InsightsLocalDataSource {
  const InsightsLocalDataSource(this._database);

  final AppDatabase _database;

  Future<InsightsSnapshot> load({int deadAfterDays = 60}) async {
    final List<Map<String, Object?>> rows =
        await _database.db.query('v_item_activity');
    final List<ItemInsight> items =
        rows.map(ItemInsight.fromRow).toList(growable: false);

    final List<ItemInsight> dead = items
        .where((ItemInsight i) =>
            i.stockMilli > 0 &&
            (i.daysSinceSold == null || i.daysSinceSold! >= deadAfterDays))
        .toList()
      ..sort((ItemInsight a, ItemInsight b) =>
          b.stockValue.minor.compareTo(a.stockValue.minor));

    final List<ItemInsight> sellers = items
        .where((ItemInsight i) => i.revenue30d.minor > 0)
        .toList()
      ..sort((ItemInsight a, ItemInsight b) =>
          b.revenue30d.minor.compareTo(a.revenue30d.minor));

    // Margin is ranked by what it earned, not by the percentage: a 90 % margin
    // on one sale a month is a curiosity, not a finding.
    final List<ItemInsight> margins = items
        .where((ItemInsight i) => i.profit30d.minor > 0)
        .toList()
      ..sort((ItemInsight a, ItemInsight b) =>
          b.profit30d.minor.compareTo(a.profit30d.minor));

    final List<ItemInsight> reorder =
        items.where((ItemInsight i) => i.needsReorder).toList()
          ..sort((ItemInsight a, ItemInsight b) =>
              (a.stockMilli - a.reorderLevelMilli)
                  .compareTo(b.stockMilli - b.reorderLevelMilli));

    final List<Map<String, Object?>> hourRows = await _database.db.query(
      'v_sales_by_hour',
      orderBy: 'hour_of_day',
    );

    return InsightsSnapshot(
      deadStock: dead.take(50).toList(growable: false),
      bestSellers: sellers.take(25).toList(growable: false),
      bestMargins: margins.take(25).toList(growable: false),
      needsReorder: reorder.take(50).toList(growable: false),
      hours: hourRows.map(HourOfDay.fromRow).toList(growable: false),
      deadStockValue:
          Money(dead.fold(0, (int s, ItemInsight i) => s + i.stockValue.minor)),
      stockValue:
          Money(items.fold(0, (int s, ItemInsight i) => s + i.stockValue.minor)),
    );
  }
}

abstract class InsightsRepository {
  Future<Result<InsightsSnapshot>> load({int deadAfterDays});
}

class InsightsRepositoryImpl implements InsightsRepository {
  const InsightsRepositoryImpl(this._local);

  final InsightsLocalDataSource _local;

  @override
  Future<Result<InsightsSnapshot>> load({int deadAfterDays = 60}) =>
      guard(() => _local.load(deadAfterDays: deadAfterDays));
}

void initInsightsInjection() {
  sl.registerLazySingleton<InsightsLocalDataSource>(
    () => InsightsLocalDataSource(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<InsightsRepository>(
    () => InsightsRepositoryImpl(sl<InsightsLocalDataSource>()),
  );
}
