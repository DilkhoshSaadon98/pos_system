import '../money/arithmetic.dart';

enum DiscountKind { none, percent, amount }


class DiscountSpec {
  const DiscountSpec(this.kind, this.value);

  const DiscountSpec.none()
      : kind = DiscountKind.none,
        value = 0;

  const DiscountSpec.percentBp(this.value) : kind = DiscountKind.percent;

  const DiscountSpec.amountMinor(this.value) : kind = DiscountKind.amount;

  final DiscountKind kind;
  final int value;

  bool get isEmpty => kind == DiscountKind.none || value == 0;


  int amountFor(int baseMinor) {
    if (isEmpty || baseMinor <= 0) return 0;
    final int raw = switch (kind) {
      DiscountKind.none => 0,
      DiscountKind.percent => mulDivRound(baseMinor, value, 10000),
      DiscountKind.amount => value,
    };
    return clampInt(raw, 0, baseMinor);
  }

  Map<String, Object?> toDb() => <String, Object?>{
        'discount_kind': kind.name,
        'discount_value': value,
      };

  static DiscountSpec fromDb(Object? kind, Object? value) {
    final int v = value is int ? value : int.tryParse('$value') ?? 0;
    return switch ('$kind') {
      'percent' => DiscountSpec.percentBp(v),
      'amount' => DiscountSpec.amountMinor(v),
      _ => const DiscountSpec.none(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DiscountSpec && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'DiscountSpec(${kind.name}, $value)';
}
