import '../../../../core/money/money.dart';


class DashboardSnapshot {
  const DashboardSnapshot({
    required this.day,
    required this.salesToday,
    required this.profitToday,
    required this.creditToday,
    required this.invoicesToday,
    required this.cash,
    required this.bank,
    required this.receivable,
    required this.payable,
    required this.inventoryAccount,
    required this.stockValue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.dailySeries,
    required this.topItems,
    required this.lowStock,
  });

  static final DashboardSnapshot empty = DashboardSnapshot(
    day: DateTime(2000),
    salesToday: Money.zero,
    profitToday: Money.zero,
    creditToday: Money.zero,
    invoicesToday: 0,
    cash: Money.zero,
    bank: Money.zero,
    receivable: Money.zero,
    payable: Money.zero,
    inventoryAccount: Money.zero,
    stockValue: Money.zero,
    lowStockCount: 0,
    outOfStockCount: 0,
    dailySeries: const <DailyPoint>[],
    topItems: const <TopItem>[],
    lowStock: const <LowStockItem>[],
  );

  final DateTime day;
  final Money salesToday;
  final Money profitToday;
  final Money creditToday;
  final int invoicesToday;
  final Money cash;
  final Money bank;
  final Money receivable;
  final Money payable;
  final Money inventoryAccount;
  final Money stockValue;
  final int lowStockCount;
  final int outOfStockCount;
  final List<DailyPoint> dailySeries;
  final List<TopItem> topItems;
  final List<LowStockItem> lowStock;

  Money get inventoryGap =>
      Money(inventoryAccount.minor - stockValue.minor);

  int get seriesPeak => dailySeries.fold(
        1,
        (int max, DailyPoint p) =>
            p.total.minor > max ? p.total.minor : max,
      );
}

class DailyPoint {
  const DailyPoint({
    required this.day,
    required this.total,
    required this.profit,
  });

  final String day;
  final Money total;
  final Money profit;
}

class TopItem {
  const TopItem({
    required this.name,
    required this.qtyMilli,
    required this.total,
  });

  final String name;
  final int qtyMilli;
  final Money total;
}

class LowStockItem {
  const LowStockItem({
    required this.id,
    required this.name,
    required this.qtyMilli,
    required this.reorderMilli,
    required this.unitName,
  });

  final int id;
  final String name;
  final int qtyMilli;
  final int reorderMilli;
  final String unitName;

  double get fraction =>
      reorderMilli <= 0 ? 0 : (qtyMilli / reorderMilli).clamp(0, 1).toDouble();
}
