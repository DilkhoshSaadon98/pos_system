import '../money/arithmetic.dart';
import 'discount.dart';

/// How a purchase is costed.
///
/// The number that matters here is not the invoice total — it is the **landed
/// cost of one base unit**, because that is what every future sale's profit is
/// measured against. Getting it right means three things the old app did not
/// do:
///
/// * A supplier discount **reduces the cost of the goods**, it is not income.
///   It is spread across the lines it was earned on.
/// * Freight and handling fees are **added to the cost of the goods** (landed
///   cost), spread the same way, rather than disappearing into an expense that
///   makes every future sale look more profitable than it was.
/// * Buying in one unit and selling in another is normal: a carton of 12 is
///   received as 12 sellable pieces, and the cost per piece is the landed cost
///   of the carton divided by 12 — not the carton price.
class PurchaseLineInput {
  const PurchaseLineInput({
    required this.itemId,
    required this.qtyMilli,
    required this.unitCostMinor,
    this.itemUnitId,
    this.unitName = '',
    this.factorMilli = 1000,
    this.discount = const DiscountSpec.none(),
    this.taxRateBp = 0,
    this.newSellPriceMinor,
    this.note,
    this.batchNo = '',
    this.expiryDate,
    this.productionDate,
  });

  final int itemId;

  /// Quantity in the *purchase* unit, in thousandths.
  final int qtyMilli;

  /// Cost of one purchase unit, in minor units.
  final int unitCostMinor;

  final int? itemUnitId;
  final String unitName;

  /// Base units per purchase unit, ×1000.
  final int factorMilli;

  final DiscountSpec discount;
  final int taxRateBp;

  /// The batch this delivery belongs to, for items counted that way. Empty and
  /// null for everything else, which is most of a shop.
  final String batchNo;
  final String? expiryDate;
  final String? productionDate;

  bool get hasBatch => batchNo.isNotEmpty || (expiryDate ?? '').isNotEmpty;

  /// Optional new selling price to write onto the item when the invoice posts.
  final int? newSellPriceMinor;

  final String? note;

  int get qtyBaseMilli => mulDivRound(qtyMilli, factorMilli, 1000);
}

class PurchaseLineTotals {
  const PurchaseLineTotals({
    required this.input,
    required this.grossMinor,
    required this.lineDiscountMinor,
    required this.allocDiscountMinor,
    required this.allocFeeMinor,
    required this.netMinor,
    required this.landedTotalMinor,
    required this.landedUnitCostMinor,
    required this.taxMinor,
    required this.qtyBaseMilli,
  });

  final PurchaseLineInput input;
  final int grossMinor;
  final int lineDiscountMinor;
  final int allocDiscountMinor;
  final int allocFeeMinor;

  /// After both discounts, before fees.
  final int netMinor;

  /// What these goods really cost once fees are included.
  final int landedTotalMinor;

  /// [landedTotalMinor] per **base** unit — the number that becomes the item's
  /// moving-average cost.
  final int landedUnitCostMinor;

  final int taxMinor;
  final int qtyBaseMilli;
}

class PurchaseTotals {
  const PurchaseTotals({
    required this.lines,
    required this.grossMinor,
    required this.lineDiscountMinor,
    required this.invoiceDiscountMinor,
    required this.discountTotalMinor,
    required this.subtotalMinor,
    required this.feesMinor,
    required this.taxMinor,
    required this.roundingMinor,
    required this.totalMinor,
    required this.paidMinor,
    required this.dueMinor,
    required this.inventoryValueMinor,
    required this.itemsCount,
  });

  final List<PurchaseLineTotals> lines;
  final int grossMinor;
  final int lineDiscountMinor;
  final int invoiceDiscountMinor;
  final int discountTotalMinor;

  /// Goods value after discounts, before fees and tax.
  final int subtotalMinor;

  final int feesMinor;
  final int taxMinor;
  final int roundingMinor;

  /// What is owed to the supplier.
  final int totalMinor;

  final int paidMinor;
  final int dueMinor;

  /// What goes into the inventory account: goods after discount plus fees.
  /// Always equals the sum of the lines' landed totals, to the cent.
  final int inventoryValueMinor;

  final int itemsCount;
}

class PurchaseCalculator {
  const PurchaseCalculator({this.roundingStepMinor = 0});

  final int roundingStepMinor;

  PurchaseTotals compute({
    required List<PurchaseLineInput> lines,
    DiscountSpec invoiceDiscount = const DiscountSpec.none(),
    int feesMinor = 0,
    int defaultTaxRateBp = 0,
    int paidMinor = 0,
  }) {
    final int n = lines.length;
    final List<int> gross = List<int>.filled(n, 0);
    final List<int> lineDiscount = List<int>.filled(n, 0);
    final List<int> net0 = List<int>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      final PurchaseLineInput l = lines[i];
      final int g = mulDivRound(l.unitCostMinor, l.qtyMilli, 1000);
      gross[i] = g;
      lineDiscount[i] = l.discount.amountFor(g);
      net0[i] = g - lineDiscount[i];
    }

    final int discountBase = net0.fold(0, (int a, int b) => a + b);
    final int invoiceDiscountMinor = invoiceDiscount.amountFor(discountBase);
    final List<int> allocDiscount = allocate(invoiceDiscountMinor, net0);

    final List<int> net = List<int>.generate(
      n,
      (int i) => net0[i] - allocDiscount[i],
      growable: false,
    );

    // Fees ride on value, not on quantity: a line worth twice as much carries
    // twice the freight. Allocated to the cent so landed totals sum exactly.
    final List<int> allocFee = allocate(feesMinor, net);

    final List<PurchaseLineTotals> result = <PurchaseLineTotals>[];
    int subtotal = 0;
    int taxTotal = 0;
    int landedTotal = 0;

    for (int i = 0; i < n; i++) {
      final PurchaseLineInput l = lines[i];
      final int landed = net[i] + allocFee[i];
      final int qtyBase = l.qtyBaseMilli;
      final int rate = l.taxRateBp > 0 ? l.taxRateBp : defaultTaxRateBp;
      final int tax = rate <= 0 ? 0 : mulDivRound(net[i], rate, 10000);

      subtotal += net[i];
      taxTotal += tax;
      landedTotal += landed;

      result.add(PurchaseLineTotals(
        input: l,
        grossMinor: gross[i],
        lineDiscountMinor: lineDiscount[i],
        allocDiscountMinor: allocDiscount[i],
        allocFeeMinor: allocFee[i],
        netMinor: net[i],
        landedTotalMinor: landed,
        landedUnitCostMinor:
            qtyBase == 0 ? 0 : mulDivRound(landed, 1000, qtyBase),
        taxMinor: tax,
        qtyBaseMilli: qtyBase,
      ));
    }

    final int beforeRounding = subtotal + feesMinor + taxTotal;
    final int rounded = roundToStep(beforeRounding, roundingStepMinor);
    final int roundingMinor = rounded - beforeRounding;
    final int total = beforeRounding + roundingMinor;
    final int applied = paidMinor > total ? total : paidMinor;

    return PurchaseTotals(
      lines: result,
      grossMinor: gross.fold(0, (int a, int b) => a + b),
      lineDiscountMinor: lineDiscount.fold(0, (int a, int b) => a + b),
      invoiceDiscountMinor: invoiceDiscountMinor,
      discountTotalMinor:
          lineDiscount.fold(0, (int a, int b) => a + b) + invoiceDiscountMinor,
      subtotalMinor: subtotal,
      feesMinor: feesMinor,
      taxMinor: taxTotal,
      roundingMinor: roundingMinor,
      totalMinor: total,
      paidMinor: applied,
      dueMinor: total - applied,
      inventoryValueMinor: landedTotal,
      itemsCount: n,
    );
  }
}
