import '../../../../core/calc/discount.dart';
import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/money/money.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';

class PosLine {
  final Item item;
  final ItemUnit unit;
  final Qty qty;
  final Money unitPrice;
  final DiscountSpec discount;
  final bool isGift;
  final String? note;

  final int? promotionId;
  final String? promotionName;
  final int promotionFreeMilli;
  const PosLine({
    required this.item,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    this.discount = const DiscountSpec.none(),
    this.isGift = false,
    this.note,
    this.promotionId,
    this.promotionName,
    this.promotionFreeMilli = 0,
  });

  bool get hasPromotion => promotionId != null;

  bool matches(Item other, ItemUnit otherUnit, {required bool gift}) =>
      item.id == other.id && unit.id == otherUnit.id && isGift == gift;

  Qty get qtyBase => Qty((qty.milli * unit.factorMilli) ~/ 1000);

  Money get gross => Money((unitPrice.minor * qty.milli) ~/ 1000);

  PosLine copyWith({
    Qty? qty,
    Money? unitPrice,
    DiscountSpec? discount,
    bool? isGift,
    String? note,
    ItemUnit? unit,
    int? promotionId,
    String? promotionName,
    int? promotionFreeMilli,
    bool clearPromotion = false,
  }) =>
      PosLine(
        item: item,
        unit: unit ?? this.unit,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        isGift: isGift ?? this.isGift,
        note: note ?? this.note,
        promotionId: clearPromotion ? null : (promotionId ?? this.promotionId),
        promotionName:
            clearPromotion ? null : (promotionName ?? this.promotionName),
        promotionFreeMilli: clearPromotion
            ? 0
            : (promotionFreeMilli ?? this.promotionFreeMilli),
      );

  SaleLineInput toInput({required int defaultTaxRateBp}) => SaleLineInput(
        itemId: item.id,
        qtyMilli: qty.milli,
        unitPriceMinor: unitPrice.minor,
        itemUnitId: unit.id,
        unitName: unit.unitName,
        factorMilli: unit.factorMilli,
        discount: discount,
        taxRateBp: item.taxRateBp > 0 ? item.taxRateBp : defaultTaxRateBp,
        unitCostMinor:
            item.kind == ItemKind.service ? 0 : item.effectiveCost.minor,
        isGift: isGift,
        note: note,
        promotionId: promotionId,
      );
}

class HeldCart {
  final int id;
  final int slotNo;
  final int lineCount;
  final String createdAt;

  final int totalMinor;

  final String? label;
  final String? partyName;
  const HeldCart({
    required this.id,
    required this.slotNo,
    required this.lineCount,
    required this.createdAt,
    required this.totalMinor,
    this.label,
    this.partyName,
  });

  factory HeldCart.fromMap(Map<String, Object?> m) => HeldCart(
        id: m['id'] as int,
        slotNo: m['slot_no'] as int,
        lineCount: m['line_count'] as int? ?? 0,
        createdAt: '${m['created_at']}',
        totalMinor: (m['total_minor'] as num?)?.toInt() ?? 0,
        label: m['label'] as String?,
        partyName: m['party_name'] as String?,
      );

  Money get total => Money(totalMinor);
}


class PosConfig {
  const PosConfig({
    this.defaultTaxRateBp = 0,
    this.pricesIncludeTax = false,
    this.roundingStepMinor = 0,
    this.defaultPriceMode = PriceMode.retail,
    this.autoPrint = true,
    this.allowNegativeStock = false,
    this.cartSlots = 12,
    this.enforceMinPrice = true,
    this.shopName = '',
    this.enforceCreditLimit = true,
  });


  final String shopName;

  final int defaultTaxRateBp;
  final bool pricesIncludeTax;
  final int roundingStepMinor;
  final PriceMode defaultPriceMode;
  final bool autoPrint;
  final bool allowNegativeStock;
  final int cartSlots;

  final bool enforceMinPrice;

  final bool enforceCreditLimit;

  SaleCalculator get calculator => SaleCalculator(
        pricesIncludeTax: pricesIncludeTax,
        roundingStepMinor: roundingStepMinor,
      );
}
