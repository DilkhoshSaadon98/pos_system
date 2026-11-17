//? One line the cashier chose to take back.
class SaleReturnLine {
  
  final int originLineId;
  final int itemId;
  final int qtyMilli;
  final int unitPriceMinor;
  final int unitCostMinor;
  final int factorMilli;
  final int taxRateBp;
  final int? itemUnitId;
  final String unitName;
  final int discountMinor;
  const SaleReturnLine({
    required this.originLineId,
    required this.itemId,
    required this.qtyMilli,
    required this.unitPriceMinor,
    required this.unitCostMinor,
    required this.factorMilli,
    required this.taxRateBp,
    this.itemUnitId,
    this.unitName = '',
    this.discountMinor = 0,
  });

//? The quantity in the base unit, calculated from the chosen unit and factor.
  int get qtyBaseMilli => (qtyMilli * factorMilli) ~/ 1000;
}
