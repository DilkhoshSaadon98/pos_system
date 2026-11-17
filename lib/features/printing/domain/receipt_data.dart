/// Everything a receipt needs, gathered once and handed to whichever printer
/// is going to render it.
///
/// The renderers (thermal roll, A4 sheet, on-screen preview) all read this same
/// object, so a change to what a receipt says is made in one place instead of
/// three.
class ReceiptData {
  const ReceiptData({
    required this.title,
    required this.documentNo,
    required this.issuedAt,
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.serviceMinor,
    required this.roundingMinor,
    required this.totalMinor,
    required this.paidMinor,
    required this.changeMinor,
    required this.dueMinor,
    required this.tenders,
    this.businessName = '',
    this.businessPhone = '',
    this.businessAddress = '',
    this.headerText = '',
    this.footerText = '',
    this.partyName,
    this.partyPhone,
    this.cashierName,
    this.note,
    this.showBarcode = true,
    this.logoPath,
  });

  final String title;
  final String documentNo;
  final String issuedAt;
  final List<ReceiptLine> lines;

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int serviceMinor;
  final int roundingMinor;
  final int totalMinor;
  final int paidMinor;
  final int changeMinor;
  final int dueMinor;

  final List<ReceiptTender> tenders;

  final String businessName;
  final String businessPhone;
  final String businessAddress;
  final String headerText;
  final String footerText;

  final String? partyName;
  final String? partyPhone;
  final String? cashierName;
  final String? note;
  final bool showBarcode;
  final String? logoPath;

  int get itemCount => lines.length;

  int get unitsMilli =>
      lines.fold(0, (int sum, ReceiptLine l) => sum + l.qtyMilli);
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qtyMilli,
    required this.unitName,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.totalMinor,
    this.isGift = false,
  });

  final String name;
  final int qtyMilli;
  final String unitName;
  final int unitPriceMinor;
  final int discountMinor;
  final int totalMinor;
  final bool isGift;
}

class ReceiptTender {
  const ReceiptTender({
    required this.method,
    required this.amountMinor,
    this.currencyCode = '',
    this.amountFxMinor = 0,
    this.fxRateMilli = 0,
  });

  final String method;

  /// Always in the shop's own currency.
  final int amountMinor;

  /// What the customer actually handed over, when it was not the shop's own
  /// money. A receipt that says only "13,200 IQD" to someone who paid ten
  /// dollars is a receipt they cannot check.
  final String currencyCode;
  final int amountFxMinor;
  final int fxRateMilli;

  bool get isForeign => currencyCode.isNotEmpty && amountFxMinor != 0;

  /// `$10.00` — written the way that currency is written.
  String get foreignText {
    final int whole = amountFxMinor.abs() ~/ 100;
    final int rest = amountFxMinor.abs() % 100;
    return '$whole.${rest.toString().padLeft(2, '0')} $currencyCode';
  }

  /// `1 USD = 1,320` — the rate this money was taken at, not today's.
  String get rateText {
    final int whole = fxRateMilli ~/ 1000;
    final int frac = fxRateMilli % 1000;
    final String r = frac == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(3, '0').replaceAll(RegExp(r'0+\$'), '')}';
    return '1 $currencyCode = $r';
  }
}
