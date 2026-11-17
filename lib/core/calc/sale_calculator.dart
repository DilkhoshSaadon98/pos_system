import '../money/arithmetic.dart';
import 'discount.dart';

/// How a sale is priced, start to finish.
///
/// This file is the single authority for every number that appears on a sales
/// invoice. The POS screen, the receipt, the journal posting and the profit
/// report all read the same [SaleTotals] — there is no second place where a
/// total is computed differently, which is exactly how the old app ended up
/// with a cart total that did not match its own printed invoice.
///
/// The order of operations, once, in words:
///
/// 1. **Line gross** = unit price × quantity.
/// 2. **Line discount** — percentage of that line's gross, or a typed amount,
///    clamped so it can never exceed the line. A gift line is a 100 % discount.
/// 3. **Invoice discount** — computed on the sum of the discounted lines, then
///    *allocated back onto the lines* proportionally, to the exact cent. Every
///    line therefore knows what it really sold for, so profit per item stays
///    honest even when the cashier gives a round number off the whole bill.
/// 4. **Tax** — per line, on the line's final net. Prices can be entered
///    tax-inclusive or tax-exclusive; the setting decides whether tax is pulled
///    out of the net or added on top.
/// 5. **Service charge**, then **cash rounding** to the configured step, with
///    the difference kept as its own figure so it can be posted to its own
///    account.
/// 6. **Tenders** — what the customer actually handed over. Change comes only
///    out of cash; anything still unpaid becomes the customer's debt.
class SaleLineInput {
  const SaleLineInput({
    required this.itemId,
    required this.qtyMilli,
    required this.unitPriceMinor,
    this.itemUnitId,
    this.unitName = '',
    this.factorMilli = 1000,
    this.discount = const DiscountSpec.none(),
    this.taxRateBp = 0,
    this.unitCostMinor = 0,
    this.promotionId,
    this.isGift = false,
    this.note,
  });

  final int itemId;

  /// Quantity in the *selling* unit, in thousandths.
  final int qtyMilli;

  /// Price of one selling unit, in minor units.
  final int unitPriceMinor;

  final int? itemUnitId;
  final String unitName;

  /// Base units contained in one selling unit, ×1000. A carton of 12 pieces is
  /// `12000` when the base unit is the piece.
  final int factorMilli;

  final DiscountSpec discount;
  final int taxRateBp;

  /// Moving-average cost of one **base** unit at the moment of sale.
  final int unitCostMinor;

  /// The offer that set this line's discount, when one did. Kept so a receipt
  /// can name it and a report can say what the promotion actually cost.
  final int? promotionId;

  final bool isGift;
  final String? note;

  /// Quantity in base units — what actually leaves the shelf.
  int get qtyBaseMilli => mulDivRound(qtyMilli, factorMilli, 1000);
}

class SaleLineTotals {
  const SaleLineTotals({
    required this.input,
    required this.grossMinor,
    required this.lineDiscountMinor,
    required this.allocDiscountMinor,
    required this.netMinor,
    required this.taxableMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.costMinor,
    required this.discountTaxableMinor,
  });

  final SaleLineInput input;

  /// Price × quantity, before any discount.
  final int grossMinor;

  /// Discount typed on the line itself.
  final int lineDiscountMinor;

  /// This line's share of the invoice-level discount.
  final int allocDiscountMinor;

  /// What the line finally sells for, tax included when prices are inclusive.
  final int netMinor;

  /// The part of [netMinor] that is not tax.
  final int taxableMinor;

  final int taxMinor;

  /// [taxableMinor] + [taxMinor] — the line's contribution to the invoice.
  final int totalMinor;

  /// Cost of goods for this line, at moving-average cost.
  final int costMinor;

  /// The tax-free part of this line's discounts. When prices exclude tax it is
  /// simply the discount; when they include tax it is the discount minus the
  /// tax inside it. The accounting posting needs this figure to show discounts
  /// as their own line in the income statement and still balance to the cent.
  final int discountTaxableMinor;

  int get discountTotalMinor => lineDiscountMinor + allocDiscountMinor;

  int get profitMinor => taxableMinor - costMinor;
}

enum TenderMethod { cash, card, bank, voucher, credit }

class TenderInput {
  const TenderInput({
    required this.method,
    required this.amountMinor,
    this.accountId,
    this.reference,
    this.currencyCode = '',
    this.fxRateMilli = 0,
    this.amountFxMinor = 0,
  });

  final TenderMethod method;

  /// Always in the shop's own currency — this is the number every total and
  /// every posting is built from. Money taken in another currency is converted
  /// once, at the till, and the original is kept in the three fields below so
  /// a receipt can show what actually changed hands.
  final int amountMinor;

  final int? accountId;
  final String? reference;

  /// Empty for the shop's own currency; `USD` and the like otherwise.
  final String currencyCode;

  /// The rate this money was taken at — see `core/money/fx.dart` for what the
  /// number means. Kept on the tender because a rate typed today must not
  /// rewrite a receipt printed last month.
  final int fxRateMilli;

  /// What the customer handed over, in that currency's own minor units.
  final int amountFxMinor;

  bool get isForeign => currencyCode.isNotEmpty && amountFxMinor != 0;
}

class SaleTotals {
  const SaleTotals({
    required this.lines,
    required this.grossMinor,
    required this.lineDiscountMinor,
    required this.invoiceDiscountMinor,
    required this.discountTotalMinor,
    required this.discountTaxableMinor,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.serviceChargeMinor,
    required this.roundingMinor,
    required this.totalMinor,
    required this.paidMinor,
    required this.changeMinor,
    required this.dueMinor,
    this.creditMinor = 0,
    required this.costMinor,
    required this.profitMinor,
    required this.itemsCount,
    required this.unitsCountMilli,
  });

  final List<SaleLineTotals> lines;

  final int grossMinor;
  final int lineDiscountMinor;
  final int invoiceDiscountMinor;
  final int discountTotalMinor;

  /// The tax-free part of all discounts — what the discount account is debited
  /// with when the invoice is posted.
  final int discountTaxableMinor;

  /// Sum of the lines' taxable amounts — revenue before tax.
  final int subtotalMinor;

  final int taxMinor;
  final int serviceChargeMinor;

  /// Positive when rounding the bill *up*, negative when rounding down.
  final int roundingMinor;

  /// What the customer owes for this invoice.
  final int totalMinor;

  /// Of the tenders, the part that settles this invoice.
  final int paidMinor;

  /// Cash handed back.
  final int changeMinor;

  /// Left on the customer's account.
  final int dueMinor;

  /// Non-cash overpayment, left as a credit on the customer's account.
  final int creditMinor;

  final int costMinor;
  final int profitMinor;

  final int itemsCount;
  final int unitsCountMilli;

  bool get isFullyPaid => dueMinor == 0;
}

class SaleCalculator {
  const SaleCalculator({
    this.pricesIncludeTax = false,
    this.roundingStepMinor = 0,
  });

  /// When true, the prices on items already contain the tax and it is extracted
  /// from the net rather than added to it.
  final bool pricesIncludeTax;

  /// Cash rounding step in minor units — 25000 rounds bills to the nearest 250.
  final int roundingStepMinor;

  SaleTotals compute({
    required List<SaleLineInput> lines,
    DiscountSpec invoiceDiscount = const DiscountSpec.none(),
    int defaultTaxRateBp = 0,
    int serviceChargeMinor = 0,
    List<TenderInput> tenders = const <TenderInput>[],
  }) {
    // ---- 1 & 2: line gross and the discount typed on the line --------------
    final int n = lines.length;
    final List<int> gross = List<int>.filled(n, 0);
    final List<int> lineDiscount = List<int>.filled(n, 0);
    final List<int> net0 = List<int>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      final SaleLineInput l = lines[i];
      final int g = mulDivRound(l.unitPriceMinor, l.qtyMilli, 1000);
      gross[i] = g;
      lineDiscount[i] = l.isGift ? g : l.discount.amountFor(g);
      net0[i] = g - lineDiscount[i];
    }

    // ---- 3: invoice discount, allocated back onto the lines ----------------
    final int discountBase = net0.fold(0, (int a, int b) => a + b);
    final int invoiceDiscountMinor = invoiceDiscount.amountFor(discountBase);
    final List<int> allocDiscount = allocate(invoiceDiscountMinor, net0);

    // ---- 4: tax, per line, on what the line finally sold for ---------------
    final List<SaleLineTotals> result = <SaleLineTotals>[];
    int subtotal = 0;
    int taxTotal = 0;
    int costTotal = 0;
    int discountTaxableTotal = 0;
    int unitsMilli = 0;

    for (int i = 0; i < n; i++) {
      final SaleLineInput l = lines[i];
      final int net = net0[i] - allocDiscount[i];
      final int rate = l.taxRateBp > 0 ? l.taxRateBp : defaultTaxRateBp;

      late final int taxable;
      late final int tax;
      if (rate <= 0) {
        taxable = net;
        tax = 0;
      } else if (pricesIncludeTax) {
        // net already contains the tax: base = net / (1 + rate)
        taxable = mulDivRound(net, 10000, 10000 + rate);
        tax = net - taxable;
      } else {
        taxable = net;
        tax = mulDivRound(net, rate, 10000);
      }

      final int cost = mulDivRound(l.unitCostMinor, l.qtyBaseMilli, 1000);

      final int discountRaw = lineDiscount[i] + allocDiscount[i];
      final int discountTaxable = (rate > 0 && pricesIncludeTax)
          ? mulDivRound(discountRaw, 10000, 10000 + rate)
          : discountRaw;

      subtotal += taxable;
      taxTotal += tax;
      costTotal += cost;
      discountTaxableTotal += discountTaxable;
      unitsMilli += l.qtyMilli;

      result.add(SaleLineTotals(
        input: l,
        grossMinor: gross[i],
        lineDiscountMinor: lineDiscount[i],
        allocDiscountMinor: allocDiscount[i],
        netMinor: net,
        taxableMinor: taxable,
        taxMinor: tax,
        totalMinor: taxable + tax,
        costMinor: cost,
        discountTaxableMinor: discountTaxable,
      ));
    }

    // ---- 5: service charge and cash rounding -------------------------------
    final int beforeRounding = subtotal + taxTotal + serviceChargeMinor;
    final int rounded = roundToStep(beforeRounding, roundingStepMinor);
    final int roundingMinor = rounded - beforeRounding;
    final int total = beforeRounding + roundingMinor;

    // ---- 6: tenders, change and what is left on account --------------------
    int tendered = 0;
    int cashTendered = 0;
    for (final TenderInput t in tenders) {
      if (t.method == TenderMethod.credit) continue;
      tendered += t.amountMinor;
      if (t.method == TenderMethod.cash) cashTendered += t.amountMinor;
    }

    final int applied = tendered > total ? total : tendered;
    final int overpaid = tendered - applied;
    // Change is only ever given from cash. Overpaying by card or bank is not
    // change — it stays as a credit on the customer's account.
    final int change = overpaid > cashTendered ? cashTendered : overpaid;
    final int credit = overpaid - change;
    final int due = total - applied;

    final int lineDiscountTotal =
        lineDiscount.fold(0, (int a, int b) => a + b);

    return SaleTotals(
      lines: result,
      grossMinor: gross.fold(0, (int a, int b) => a + b),
      lineDiscountMinor: lineDiscountTotal,
      invoiceDiscountMinor: invoiceDiscountMinor,
      discountTotalMinor: lineDiscountTotal + invoiceDiscountMinor,
      discountTaxableMinor: discountTaxableTotal,
      subtotalMinor: subtotal,
      taxMinor: taxTotal,
      serviceChargeMinor: serviceChargeMinor,
      roundingMinor: roundingMinor,
      totalMinor: total,
      paidMinor: applied,
      changeMinor: change,
      dueMinor: due,
      creditMinor: credit,
      costMinor: costTotal,
      profitMinor: subtotal - costTotal,
      itemsCount: n,
      unitsCountMilli: unitsMilli,
    );
  }
}
