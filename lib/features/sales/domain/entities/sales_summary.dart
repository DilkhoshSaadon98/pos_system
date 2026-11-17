import 'package:cashier_system_v2/core/money/money.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';

//? The totals under the sales list — the day's takings, in one row.
class SalesSummary {
  final Money total;
  final Money paid;
  final Money due;
  final Money profit;
  final Money discount;
  final Money tax;
  final int count;
  final Money returnsTotal;
  const SalesSummary({
    required this.total,
    required this.paid,
    required this.due,
    required this.profit,
    required this.discount,
    required this.tax,
    required this.count,
    required this.returnsTotal,
  });

  static const SalesSummary empty = SalesSummary(
    total: Money.zero,
    paid: Money.zero,
    due: Money.zero,
    profit: Money.zero,
    discount: Money.zero,
    tax: Money.zero,
    count: 0,
    returnsTotal: Money.zero,
  );

  static SalesSummary of(List<SaleInvoice> invoices) {
    int total = 0;
    int paid = 0;
    int due = 0;
    int profit = 0;
    int discount = 0;
    int tax = 0;
    int returns = 0;

    for (final SaleInvoice i in invoices) {
      if (i.isVoid) continue;
      final int sign = i.isReturn ? -1 : 1;
      total += sign * i.total.minor;
      paid += sign * i.paid.minor;
      due += sign * i.due.minor;
      profit += sign * i.profit.minor;
      discount += sign * i.discount.minor;
      tax += sign * i.tax.minor;
      if (i.isReturn) returns += i.total.minor;
    }

    return SalesSummary(
      total: Money(total),
      paid: Money(paid),
      due: Money(due),
      profit: Money(profit),
      discount: Money(discount),
      tax: Money(tax),
      count: invoices.where((SaleInvoice i) => !i.isVoid).length,
      returnsTotal: Money(returns),
    );
  }
}
