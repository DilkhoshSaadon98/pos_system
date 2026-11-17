import '../money/money.dart';

/// Reading the barcode a shop scale prints.
///
/// A scale does not know what a kilo of tomatoes costs — it knows what *this*
/// bag weighs, so it prints a code that carries the weight (or the price) in
/// the barcode itself. Every one of them uses the same GS1 in-store shape:
///
/// ```
///   2 1  1 2 3 4 5   0 1 2 5 0   7
///   └┬─┘ └────┬────┘ └────┬────┘ └┬┘
///  prefix  item code   payload   check
/// ```
///
/// The prefix says "this is an in-store code" (GS1 reserves 20–29 for it), the
/// five middle digits identify the product, the next five are either grams or
/// minor units of money depending on how the scale is configured, and the last
/// is the EAN-13 check digit.
///
/// Which of the two the payload is cannot be guessed — a 1 250 could be 1.25 kg
/// or 12.50 of currency — so it is a setting, and the parser reports what it
/// found rather than deciding what to do about it.
class ScaleBarcode {
  const ScaleBarcode._();

  /// Splits [code] into its parts, or returns null when it is an ordinary
  /// barcode. A null result is not an error: most scans are just barcodes.
  static ScaleScan? parse(
    String code, {
    required List<String> prefixes,
    required bool payloadIsWeight,
    int weightDecimals = 3,
  }) {
    final String digits = code.trim();
    if (digits.length != 13) return null;
    if (!RegExp(r'^[0-9]{13}$').hasMatch(digits)) return null;

    final String prefix = digits.substring(0, 2);
    if (!prefixes.contains(prefix)) return null;
    if (!hasValidCheckDigit(digits)) return null;

    final String itemCode = digits.substring(2, 7);
    final int payload = int.parse(digits.substring(7, 12));

    if (payloadIsWeight) {
      // Five digits of grams at three decimals: 01250 → 1.250 kg → Qty(1250).
      final int scale = _pow10(weightDecimals);
      final int milli = scale == 1000
          ? payload
          : (payload * 1000) ~/ (scale == 0 ? 1 : scale);
      return ScaleScan(
        prefix: prefix,
        itemCode: itemCode,
        qty: Qty(milli),
      );
    }

    // Payload is money, in minor units of the display currency. The till turns
    // it into a quantity once it knows the item's price per unit.
    return ScaleScan(
      prefix: prefix,
      itemCode: itemCode,
      amount: Money(payload * 100 ~/ 100),
    );
  }

  /// The quantity implied by a price-carrying label: amount ÷ unit price.
  ///
  /// Rounded to the thousandth, which is the resolution the rest of the app
  /// keeps quantities in. A zero price gives zero rather than infinity — the
  /// till then asks for the weight by hand.
  static Qty quantityForAmount(Money amount, Money unitPrice) {
    if (unitPrice.minor <= 0) return Qty.zero;
    return Qty((amount.minor * 1000) ~/ unitPrice.minor);
  }

  /// EAN-13: odd positions ×1, even ×3, the total rounded up to a multiple of
  /// ten. Checking it costs nothing and stops a misread label from being taken
  /// as a two-kilo sale.
  static bool hasValidCheckDigit(String digits) {
    if (digits.length != 13) return false;
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final int d = digits.codeUnitAt(i) - 48;
      sum += (i.isEven) ? d : d * 3;
    }
    final int check = (10 - (sum % 10)) % 10;
    return check == digits.codeUnitAt(12) - 48;
  }

  /// Builds the label a scale would print — used by the item editor to show
  /// the shopkeeper exactly what to program into the scale.
  static String build({
    required String prefix,
    required String itemCode,
    required int payload,
  }) {
    final String body = prefix.padLeft(2, '0') +
        itemCode.padLeft(5, '0') +
        payload.toString().padLeft(5, '0').substring(0, 5);
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final int d = body.codeUnitAt(i) - 48;
      sum += (i.isEven) ? d : d * 3;
    }
    final int check = (10 - (sum % 10)) % 10;
    return '$body$check';
  }

  static int _pow10(int n) {
    int v = 1;
    for (int i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}

/// What a scale label turned out to say.
class ScaleScan {
  const ScaleScan({
    required this.prefix,
    required this.itemCode,
    this.qty,
    this.amount,
  });

  final String prefix;

  /// The five digits that identify the product — matched against
  /// `items.scale_code`.
  final String itemCode;

  /// Set when the label carries a weight.
  final Qty? qty;

  /// Set when the label carries a price instead.
  final Money? amount;

  bool get isWeight => qty != null;
}
