import '../money/arithmetic.dart';


class Costing {
  const Costing._();

//? Calculates the new average cost after a receipt is received.
  static int averageAfterReceipt({
    required int onHandMilli,
    required int currentAvgMinor,
    required int receivedMilli,
    required int receivedUnitCostMinor,
  }) {
    if (receivedMilli <= 0) return currentAvgMinor;
    if (onHandMilli <= 0) return receivedUnitCostMinor;

    final int currentValue = mulDivRound(currentAvgMinor, onHandMilli, 1000);
    final int receivedValue =
        mulDivRound(receivedUnitCostMinor, receivedMilli, 1000);
    final int totalQty = onHandMilli + receivedMilli;
    if (totalQty == 0) return receivedUnitCostMinor;

    return mulDivRound(currentValue + receivedValue, 1000, totalQty);
  }

 //? Calculates the new average cost after a stock adjustment is made.
  static int issueValue({
    required int qtyMilli,
    required int avgCostMinor,
  }) =>
      mulDivRound(avgCostMinor, qtyMilli, 1000);


  static int stockValue({
    required int qtyMilli,
    required int avgCostMinor,
  }) =>
      mulDivRound(avgCostMinor, qtyMilli, 1000);


  static int returnToSupplierUnitCost({
    required int originalLandedUnitCostMinor,
    required int currentAvgMinor,
  }) =>
      originalLandedUnitCostMinor > 0
          ? originalLandedUnitCostMinor
          : currentAvgMinor;


  static int returnFromCustomerUnitCost({
    required int originalUnitCostMinor,
    required int currentAvgMinor,
  }) =>
      originalUnitCostMinor > 0 ? originalUnitCostMinor : currentAvgMinor;

//? Calculates the price given the unit cost and margin in basis points (bp).
  static int priceForMargin({
    required int unitCostMinor,
    required int marginBp,
  }) {
    if (marginBp <= 0) return unitCostMinor;
    if (marginBp >= 10000) return unitCostMinor;
    return mulDivRound(unitCostMinor, 10000, 10000 - marginBp);
  }
//? Calculates the margin in basis points (bp) given the price and unit cost.
  static int marginBpOf({
    required int priceMinor,
    required int unitCostMinor,
  }) {
    if (priceMinor <= 0) return 0;
    return mulDivRound(priceMinor - unitCostMinor, 10000, priceMinor);
  }
}
