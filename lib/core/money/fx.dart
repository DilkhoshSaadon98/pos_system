import '../database/app_database.dart';
import 'arithmetic.dart';

/// The shop's second currency, and the one number that connects it to the
/// first.
///
/// The price list is in one currency and a good part of the takings arrive in
/// another. Everything the books hold stays in the shop's own currency; the
/// foreign side is converted at the moment the money changes hands, and the
/// rate that was used is written onto the tender so a receipt reprinted next
/// month still shows the truth of that day.
///
/// ## Storage, and why the rate looks the way it does
///
/// Every amount in this app — in either currency — is stored as **hundredths**,
/// exactly like [Money]. How many decimals a currency is *written* with is a
/// display choice ([decimals]); it never changes what is stored. Because both
/// sides of a conversion are held at the same scale, the rate is simply the
/// human rate with three decimal places of headroom:
///
/// ```
///   1 USD = 1,320 IQD        → rateMilli = 1,320,000
///   $10 handed over          → 1,000 hundredths of a dollar
///   base = mulDivRound(1000, 1320000, 1000) = 1,320,000 hundredths = 13,200 IQD
/// ```
///
/// One multiply, one divide, one rounding, and no floating point anywhere near
/// the drawer.
class FxRate {
  const FxRate({
    required this.enabled,
    required this.code,
    required this.symbol,
    required this.decimals,
    required this.rateMilli,
    required this.changeRoundingMinor,
  });

  /// The state a shop is in before anyone sets a rate: no second currency.
  static const FxRate off = FxRate(
    enabled: false,
    code: '',
    symbol: '',
    decimals: 2,
    rateMilli: 0,
    changeRoundingMinor: 0,
  );

  final bool enabled;

  /// `USD`. Written onto every tender taken in this currency.
  final String code;
  final String symbol;

  /// How the foreign currency is *written* — 2 for dollars, 0 for a currency
  /// without small change. Display only; storage is always hundredths.
  final int decimals;

  /// The human rate times 1000: `1 USD = 1,320 IQD` → 1,320,000.
  final int rateMilli;

  /// Change for a foreign note is given in the shop's own currency, and no
  /// drawer holds a 3-dinar coin. Rounds the change to something a cashier can
  /// actually hand over; 0 turns it off.
  final int changeRoundingMinor;

  bool get isUsable => enabled && rateMilli > 0 && code.isNotEmpty;

  /// Reads the `fx_*` settings. Safe on a database that has never seen them:
  /// an unset or nonsense rate yields [off] rather than a currency that
  /// silently prices dollars at zero.
  factory FxRate.fromSettings(AppDatabase database) {
    final bool enabled = database.settingBool('fx_enabled', false);
    final String code = database.settingString('fx_currency_code');
    final int rateMilli = rateMilliFrom(database.settingString('fx_rate'));

    if (!enabled || code.isEmpty || rateMilli <= 0) return off;

    return FxRate(
      enabled: true,
      code: code,
      symbol: database.settingString('fx_currency_symbol', code),
      decimals: database.settingInt('fx_decimals', 2),
      rateMilli: rateMilli,
      changeRoundingMinor: database.settingInt('fx_change_rounding'),
    );
  }

  /// What [fxMinor] of the foreign currency is worth in the shop's own.
  int toBase(int fxMinor) => mulDivRound(fxMinor, rateMilli, 1000);

  /// The other direction, for showing a dinar price in dollars. Display and
  /// expectations only — a posting is always built from [toBase].
  int toFx(int baseMinor) =>
      rateMilli == 0 ? 0 : mulDivRound(baseMinor, 1000, rateMilli);

  /// Change owed in the shop's own currency, rounded to what the drawer can
  /// actually pay.
  int roundChange(int baseMinor) => changeRoundingMinor <= 1
      ? baseMinor
      : roundToStep(baseMinor, changeRoundingMinor);

  /// Parses a human rate — `1320`, `1,320`, `1320.5` — into [rateMilli].
  ///
  /// Done on the string rather than through a `double` on purpose: the whole
  /// app's promise is that no money value passes through floating point, and a
  /// rate is the most leveraged number in the system — every dollar taken all
  /// day is multiplied by it.
  static int rateMilliFrom(String text) {
    final String clean = text.replaceAll(',', '').replaceAll(' ', '').trim();
    if (clean.isEmpty) return 0;

    final List<String> parts = clean.split('.');
    if (parts.length > 2) return 0;

    final int whole = int.tryParse(parts.first) ?? -1;
    if (whole < 0) return 0;

    // Three decimals of the rate are kept; more than that is noise at any
    // amount a shop actually handles.
    String frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > 3) frac = frac.substring(0, 3);
    final int fracValue = frac.isEmpty ? 0 : (int.tryParse(frac) ?? -1);
    if (fracValue < 0) return 0;

    return whole * 1000 + fracValue * _pow10(3 - frac.length);
  }

  /// The rate as a person writes it: `1320` or `1320.5`.
  String get rateText {
    final int whole = rateMilli ~/ 1000;
    final int frac = rateMilli % 1000;
    if (frac == 0) return '$whole';
    return '$whole.${frac.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '')}';
  }

  /// `$12.50` — the foreign amount written the way that currency is written.
  String format(int fxMinor) {
    final bool negative = fxMinor < 0;
    final int value = fxMinor.abs();
    final int whole = value ~/ 100;
    final int rest = value % 100;

    final String body;
    if (decimals <= 0) {
      body = '${whole + (rest >= 50 ? 1 : 0)}';
    } else if (decimals == 1) {
      body = '$whole.${(rest ~/ 10)}';
    } else {
      body = '$whole.${rest.toString().padLeft(2, '0')}';
    }

    final String sign = negative ? '-' : '';
    return symbol.isEmpty ? '$sign$body' : '$sign$symbol$body';
  }

  static int _pow10(int n) {
    int v = 1;
    for (int i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}
