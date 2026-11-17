import 'package:cashier_system_v2/core/money/money.dart';

//? One line of a saved invoice.
class SaleInvoiceLine {
  final int id;
  final int itemId;
  final String itemName;
  final String unitName;
  final int qtyMilli;
  final int qtyBaseMilli;
  final int factorMilli;
  final Money unitPrice;
  final Money gross;
  final Money discount;
  final Money net;
  final Money tax;
  final Money total;
  final Money unitCost;
  final Money cost;
  final bool isGift;
  final int returnedQtyMilli;
  final int? itemUnitId;
  final String? note;
  const SaleInvoiceLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.qtyMilli,
    required this.qtyBaseMilli,
    required this.factorMilli,
    required this.unitPrice,
    required this.gross,
    required this.discount,
    required this.net,
    required this.tax,
    required this.total,
    required this.unitCost,
    required this.cost,
    required this.isGift,
    required this.returnedQtyMilli,
    this.itemUnitId,
    this.note,
  });

  factory SaleInvoiceLine.fromMap(Map<String, Object?> m) => SaleInvoiceLine(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name'] ?? ''}',
        unitName: '${m['unit_name'] ?? ''}',
        qtyMilli: m['qty_milli'] as int? ?? 0,
        qtyBaseMilli: m['qty_base_milli'] as int? ?? 0,
        factorMilli: m['factor_milli'] as int? ?? 1000,
        unitPrice: Money.fromDb(m['unit_price_minor']),
        gross: Money.fromDb(m['gross_minor']),
        discount: Money.fromDb(
          (m['line_discount_minor'] as int? ?? 0) +
              (m['alloc_discount_minor'] as int? ?? 0),
        ),
        net: Money.fromDb(m['net_minor']),
        tax: Money.fromDb(m['tax_minor']),
        total: Money.fromDb(m['total_minor']),
        unitCost: Money.fromDb(m['unit_cost_minor']),
        cost: Money.fromDb(m['cost_minor']),
        isGift: (m['is_gift'] as int? ?? 0) == 1,
        returnedQtyMilli: m['returned_qty_milli'] as int? ?? 0,
        itemUnitId: m['item_unit_id'] as int?,
        note: m['note'] as String?,
      );

  Qty get qty => Qty(qtyMilli);

  int get returnableQtyMilli =>
      qtyMilli - returnedQtyMilli < 0 ? 0 : qtyMilli - returnedQtyMilli;

  bool get isFullyReturned => returnableQtyMilli == 0;
}
