import 'arithmetic.dart';

/// An exact amount of money, held as whole **minor units** (1/100 of the
/// currency). `1 500 IQD` is `Money(150000)`.
///
/// Two decimals of storage is enough for every currency this app is used with,
/// and keeping the scale fixed means a stored number never has to be
/// re-interpreted. How many decimals the cashier *sees* is a display setting,
/// independent of this.
class Money implements Comparable<Money> {
  const Money(this.minor);

  /// Builds from a human number, e.g. `Money.major(12.5)` → 1250 minor.
  factory Money.major(num value) => Money((value * 100).round());

  /// Reads a value out of the database, tolerating the REAL columns of the old
  /// schema during migration.
  factory Money.fromDb(Object? value) {
    if (value == null) return Money.zero;
    if (value is int) return Money(value);
    if (value is double) return Money(value.round());
    return Money(int.tryParse(value.toString()) ?? 0);
  }

  static const Money zero = Money(0);

  final int minor;

  double get major => minor / 100;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  Money operator +(Money other) => Money(minor + other.minor);
  Money operator -(Money other) => Money(minor - other.minor);
  Money operator -() => Money(-minor);

  /// Price × quantity. [qtyMilli] is a quantity in thousandths.
  Money forQty(int qtyMilli) => Money(mulDivRound(minor, qtyMilli, 1000));

  /// A share of this amount in basis points — 750 bp is 7.5 %.
  Money percentBp(int bp) => Money(mulDivRound(minor, bp, 10000));

  Money operator *(int factor) => Money(minor * factor);

  Money get abs => Money(minor.abs());

  Money clampAtLeastZero() => minor < 0 ? Money.zero : this;

  Money clampTo(Money low, Money high) =>
      Money(clampInt(minor, low.minor, high.minor));

  /// Rounds to a cash step, e.g. the nearest 250 IQD → `roundedToStep(25000)`.
  Money roundedToStep(int stepMinor) => Money(roundToStep(minor, stepMinor));

  static Money sum(Iterable<Money> values) =>
      Money(values.fold(0, (int a, Money b) => a + b.minor));

  bool operator <(Money other) => minor < other.minor;
  bool operator <=(Money other) => minor <= other.minor;
  bool operator >(Money other) => minor > other.minor;
  bool operator >=(Money other) => minor >= other.minor;

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money($minor)';
}

/// A quantity, held as whole **thousandths of a unit**, so 0.25 kg is
/// `Qty(250)` and 3 pieces are `Qty(3000)`.
class Qty implements Comparable<Qty> {
  const Qty(this.milli);

  factory Qty.units(num value) => Qty((value * 1000).round());

  factory Qty.fromDb(Object? value) {
    if (value == null) return Qty.zero;
    if (value is int) return Qty(value);
    if (value is double) return Qty(value.round());
    return Qty(int.tryParse(value.toString()) ?? 0);
  }

  static const Qty zero = Qty(0);
  static const Qty one = Qty(1000);

  final int milli;

  double get units => milli / 1000;

  bool get isZero => milli == 0;
  bool get isNegative => milli < 0;
  bool get isPositive => milli > 0;

  Qty operator +(Qty other) => Qty(milli + other.milli);
  Qty operator -(Qty other) => Qty(milli - other.milli);
  Qty operator -() => Qty(-milli);

  /// Converts a quantity expressed in a sale/purchase unit into base units.
  /// [factorMilli] is how many base units one of that unit holds, ×1000.
  Qty toBase(int factorMilli) => Qty(mulDivRound(milli, factorMilli, 1000));

  /// The inverse of [toBase].
  Qty fromBase(int factorMilli) =>
      factorMilli == 0 ? Qty.zero : Qty(mulDivRound(milli, 1000, factorMilli));

  Qty get abs => Qty(milli.abs());

  bool operator <(Qty other) => milli < other.milli;
  bool operator <=(Qty other) => milli <= other.milli;
  bool operator >(Qty other) => milli > other.milli;
  bool operator >=(Qty other) => milli >= other.milli;

  @override
  int compareTo(Qty other) => milli.compareTo(other.milli);

  @override
  bool operator ==(Object other) => other is Qty && other.milli == milli;

  @override
  int get hashCode => milli.hashCode;

  @override
  String toString() => 'Qty($milli)';
}
