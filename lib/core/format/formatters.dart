import 'package:intl/intl.dart';

import '../money/money.dart';

//? Turning stored integers into something a person reads.
class Fmt {
  Fmt._();

  static Fmt instance = Fmt._();

  String currencySymbol = 'IQD';
  int decimals = 0;
  String localeName = 'en';

  //? A number formatter that uses the current locale and decimal count.
  NumberFormat get _money => NumberFormat.decimalPatternDigits(
        locale: 'en',
        decimalDigits: decimals,
      );
//? Configures the formatter for the current shop.
  static void configure({
    required String symbol,
    required int decimals,
    required String locale,
  }) {
    instance
      ..currencySymbol = symbol
      ..decimals = decimals
      ..localeName = locale;
  }

  //? Money for a till screen: always the same width, with the currency symbol.
  static String money(Money value, {bool withSymbol = true}) =>
      moneyMinor(value.minor, withSymbol: withSymbol);
  static String moneyMinor(int minor, {bool withSymbol = true}) {
    final Fmt f = instance;
    final double shown = minor / 100;
    final String text = f._money.format(shown);
    return withSymbol ? '$text ${f.currencySymbol}' : text;
  }

  //? Money for a printed receipt: never wider than it has to be.
  static String moneyPlain(int minor) => moneyMinor(minor, withSymbol: false);

  //? `3`, `1.5`, `0.250` — trailing zeros dropped, because "3 pcs" reads
  //? better than "3.000 pcs" on a receipt.
  static String qty(Qty value) => qtyMilli(value.milli);

  static String qtyMilli(int milli) {
    if (milli % 1000 == 0) return (milli ~/ 1000).toString();
    final String s = (milli / 1000).toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  //? `7.5 %` — trailing zeros dropped, because "7.5 %" reads better than "7.500 %".
  static String percentBp(int bp) {
    final double p = bp / 100;
    final String s = p == p.roundToDouble()
        ? p.toStringAsFixed(0)
        : p.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return '$s %';
  }
  //? `2023-01-31`, `2023-01-31  14:30`, `14:30` — trailing zeros dropped, because "14:30" reads better than "14:30:00".
  static String date(String? isoish) {
    final DateTime? d = _parse(isoish);
    if (d == null) return '';
    return DateFormat('yyyy-MM-dd').format(d);
  }
//? `2023-01-31  14:30`, `14:30` — trailing zeros dropped, because "14:30" reads better than "14:30:00".
  static String dateTime(String? isoish) {
    final DateTime? d = _parse(isoish);
    if (d == null) return '';
    return DateFormat('yyyy-MM-dd  HH:mm').format(d);
  }
//? `14:30` — trailing zeros dropped, because "14:30" reads better than "14:30:00".
  static String time(String? isoish) {
    final DateTime? d = _parse(isoish);
    if (d == null) return '';
    return DateFormat('HH:mm').format(d);
  }
//? `Tuesday, 31 January` — trailing zeros dropped, because "Tuesday, 31 January" reads better than "Tuesday, 31 January 00:00".
  static String dayName(DateTime d) =>
      DateFormat('EEEE, d MMMM', instance.localeName).format(d);

  static DateTime? _parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  }
  //? `3`, `1.5`, `0.250` — trailing zeros dropped, because "3 pcs" reads
  static Money? parseMoney(String input) {
    final String cleaned = _clean(input);
    if (cleaned.isEmpty) return null;
    final double? v = double.tryParse(cleaned);
    if (v == null) return null;
    return Money.major(v);
  }
//? `3`, `1.5`, `0.250` — trailing zeros dropped, because "3 pcs" reads
  static Qty? parseQty(String input) {
    final String cleaned = _clean(input);
    if (cleaned.isEmpty) return null;
    final double? v = double.tryParse(cleaned);
    if (v == null) return null;
    return Qty.units(v);
  }

  //? A percentage typed as `7.5` becomes 750 basis points.
  static int? parsePercentBp(String input) {
    final String cleaned = _clean(input);
    if (cleaned.isEmpty) return null;
    final double? v = double.tryParse(cleaned);
    if (v == null) return null;
    return (v * 100).round();
  }

  static String _clean(String input) => input
      .trim()
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');
}
