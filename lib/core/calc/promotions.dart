import '../classes/enums.dart';
import '../money/arithmetic.dart';

/// The shapes an offer can take.
enum PromotionKind {
  /// A share off the line — "10 % off".
  percent('percent'),

  /// A fixed sum off the line — "500 off".
  amount('amount'),

  /// A replacement price for the whole line — "today, 2,000 each".
  price('price'),

  /// A cheaper price once enough is bought — "1,800 each from three up".
  quantity('quantity'),

  /// "Buy two, get one free."
  buyGet('buy_get');

  const PromotionKind(this.dbValue);

  final String dbValue;

  static PromotionKind fromDb(Object? value) =>
      PromotionKind.values.firstWhere(
        (PromotionKind k) => k.dbValue == '$value',
        orElse: () => PromotionKind.percent,
      );
}

/// One offer, as the till holds it.
class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    required this.kind,
    this.valueBp = 0,
    this.valueMinor = 0,
    this.minQtyMilli = 0,
    this.getQtyMilli = 0,
    this.scope = 'items',
    this.categoryId,
    this.startsOn,
    this.endsOn,
    this.weekdays = '',
    this.priceMode = 'any',
    this.membersOnly = false,
    this.priority = 0,
    this.itemIds = const <int>{},
  });

  factory Promotion.fromRow(
    Map<String, Object?> m, {
    Set<int> itemIds = const <int>{},
  }) =>
      Promotion(
        id: m['id'] as int,
        name: '${m['name']}',
        kind: PromotionKind.fromDb(m['kind']),
        valueBp: m['value_bp'] as int? ?? 0,
        valueMinor: m['value_minor'] as int? ?? 0,
        minQtyMilli: m['min_qty_milli'] as int? ?? 0,
        getQtyMilli: m['get_qty_milli'] as int? ?? 0,
        scope: '${m['scope'] ?? 'items'}',
        categoryId: m['category_id'] as int?,
        startsOn: m['starts_on'] as String?,
        endsOn: m['ends_on'] as String?,
        weekdays: '${m['weekdays'] ?? ''}',
        priceMode: '${m['price_mode'] ?? 'any'}',
        membersOnly: (m['members_only'] as int? ?? 0) == 1,
        priority: m['priority'] as int? ?? 0,
        itemIds: itemIds,
      );

  final int id;
  final String name;
  final PromotionKind kind;

  /// Basis points for [PromotionKind.percent]; 1000 is 10 %.
  final int valueBp;

  /// Minor units: the sum taken off, or the replacement unit price.
  final int valueMinor;

  final int minQtyMilli;
  final int getQtyMilli;

  /// `items` (the list below), `category`, or `all`.
  final String scope;
  final int? categoryId;

  final String? startsOn;
  final String? endsOn;

  /// Digits of the weekdays it runs on, Sunday = 0. Empty means every day.
  final String weekdays;

  /// `any`, `retail` or `wholesale`.
  final String priceMode;

  final bool membersOnly;

  /// Breaks a tie between two offers worth the same.
  final int priority;

  final Set<int> itemIds;

  /// Does this offer apply to this line at all?
  bool appliesTo({
    required int itemId,
    int? categoryId,
    required PriceMode mode,
    required bool isMember,
    required DateTime at,
  }) {
    if (membersOnly && !isMember) return false;
    if (priceMode != 'any' && priceMode != mode.dbValue) return false;

    final String day = _iso(at);
    if (startsOn != null && startsOn!.isNotEmpty && day.compareTo(startsOn!) < 0) {
      return false;
    }
    if (endsOn != null && endsOn!.isNotEmpty && day.compareTo(endsOn!) > 0) {
      return false;
    }

    if (weekdays.isNotEmpty) {
      // Dart counts Monday = 1 … Sunday = 7; the table stores Sunday = 0 to
      // match SQLite's strftime('%w'), which is what the views use.
      final int dow = at.weekday == DateTime.sunday ? 0 : at.weekday;
      if (!weekdays.contains('$dow')) return false;
    }

    switch (scope) {
      case 'all':
        return true;
      case 'category':
        return this.categoryId != null && this.categoryId == categoryId;
      default:
        return itemIds.contains(itemId);
    }
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// What an offer does to one line.
class PromotionOutcome {
  const PromotionOutcome({
    required this.promotionId,
    required this.name,
    required this.discountMinor,
    this.freeQtyMilli = 0,
    this.unitPriceMinor,
  });

  final int promotionId;
  final String name;

  /// What comes off the line, in minor units. Never negative, never more than
  /// the line was worth.
  final int discountMinor;

  /// For "buy two get one": how much of the line is free. Shown on the
  /// receipt, because a customer who was given something should be told.
  final int freeQtyMilli;

  /// A replacement unit price, when the offer works that way. The discount is
  /// still filled in, so a caller that only understands discounts is correct.
  final int? unitPriceMinor;

  bool get isNothing => discountMinor <= 0;
}

/// Chooses the offer a line gets.
///
/// ## One offer per line, and it is the best one
///
/// Offers are not stacked. Two promotions on the same item would raise the
/// question of what order they combine in, and every answer is arbitrary and
/// arguable at the counter. Instead the engine computes what each candidate
/// would take off, and applies the **largest** — the one the customer would
/// have asked for anyway. A tie goes to the higher `priority`, then to the
/// older promotion, so the same basket always prices the same way.
///
/// Everything is integer arithmetic on minor units and thousandths, like the
/// rest of the app: a percentage is basis points, and a free quantity is a
/// whole number of thousandths.
class PromotionEngine {
  const PromotionEngine(this.promotions);

  static const PromotionEngine none = PromotionEngine(<Promotion>[]);

  final List<Promotion> promotions;

  bool get isEmpty => promotions.isEmpty;

  /// The best offer for one cart line, or null when nothing applies.
  PromotionOutcome? bestFor({
    required int itemId,
    int? categoryId,
    required int qtyMilli,
    required int unitPriceMinor,
    PriceMode mode = PriceMode.retail,
    bool isMember = false,
    DateTime? at,
  }) {
    if (promotions.isEmpty || qtyMilli <= 0 || unitPriceMinor <= 0) return null;
    final DateTime when = at ?? DateTime.now();
    final int gross = mulDivRound(unitPriceMinor, qtyMilli, 1000);
    if (gross <= 0) return null;

    PromotionOutcome? best;
    Promotion? bestPromo;

    for (final Promotion p in promotions) {
      if (!p.appliesTo(
        itemId: itemId,
        categoryId: categoryId,
        mode: mode,
        isMember: isMember,
        at: when,
      )) {
        continue;
      }

      final PromotionOutcome? outcome = _apply(p, qtyMilli, unitPriceMinor, gross);
      if (outcome == null || outcome.isNothing) continue;

      if (best == null ||
          outcome.discountMinor > best.discountMinor ||
          (outcome.discountMinor == best.discountMinor &&
              (p.priority > (bestPromo?.priority ?? 0) ||
                  (p.priority == (bestPromo?.priority ?? 0) &&
                      p.id < (bestPromo?.id ?? 1 << 30))))) {
        best = outcome;
        bestPromo = p;
      }
    }

    return best;
  }

  PromotionOutcome? _apply(
    Promotion p,
    int qtyMilli,
    int unitPriceMinor,
    int gross,
  ) {
    switch (p.kind) {
      case PromotionKind.percent:
        if (p.valueBp <= 0) return null;
        return _outcome(p, mulDivRound(gross, p.valueBp, 10000), gross);

      case PromotionKind.amount:
        if (p.valueMinor <= 0) return null;
        return _outcome(p, p.valueMinor, gross);

      case PromotionKind.price:
        if (p.valueMinor <= 0 || p.valueMinor >= unitPriceMinor) return null;
        final int newGross = mulDivRound(p.valueMinor, qtyMilli, 1000);
        return _outcome(p, gross - newGross, gross,
            unitPriceMinor: p.valueMinor);

      case PromotionKind.quantity:
        // Only once the customer has bought enough of it.
        if (p.minQtyMilli <= 0 || qtyMilli < p.minQtyMilli) return null;
        if (p.valueMinor <= 0 || p.valueMinor >= unitPriceMinor) return null;
        final int cheaper = mulDivRound(p.valueMinor, qtyMilli, 1000);
        return _outcome(p, gross - cheaper, gross, unitPriceMinor: p.valueMinor);

      case PromotionKind.buyGet:
        final int block = p.minQtyMilli + p.getQtyMilli;
        if (p.minQtyMilli <= 0 || p.getQtyMilli <= 0 || block <= 0) return null;
        // How many complete "buy X get Y" blocks are in the line.
        final int blocks = qtyMilli ~/ block;
        if (blocks <= 0) return null;
        final int freeMilli = blocks * p.getQtyMilli;
        return _outcome(
          p,
          mulDivRound(unitPriceMinor, freeMilli, 1000),
          gross,
          freeQtyMilli: freeMilli,
        );
    }
  }

  PromotionOutcome _outcome(
    Promotion p,
    int discount,
    int gross, {
    int freeQtyMilli = 0,
    int? unitPriceMinor,
  }) {
    // An offer can never make a line negative, and never pays the customer.
    final int capped = discount < 0 ? 0 : (discount > gross ? gross : discount);
    return PromotionOutcome(
      promotionId: p.id,
      name: p.name,
      discountMinor: capped,
      freeQtyMilli: freeQtyMilli,
      unitPriceMinor: unitPriceMinor,
    );
  }
}
