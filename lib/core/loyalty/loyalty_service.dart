import 'package:sqflite_common/sqlite_api.dart';

import '../database/app_database.dart';
import '../error/exceptions.dart';
import '../money/arithmetic.dart';
import '../utils/time.dart';

//? How a shop's points scheme is set up today.
class LoyaltyRules {
  const LoyaltyRules({
    required this.enabled,
    required this.earnPerMinor,
    required this.pointValueMinor,
    required this.minRedeemPoints,
  });

  static const LoyaltyRules off = LoyaltyRules(
    enabled: false,
    earnPerMinor: 0,
    pointValueMinor: 0,
    minRedeemPoints: 0,
  );

  factory LoyaltyRules.fromSettings(AppDatabase database) {
    final bool on = database.settingBool('loyalty_enabled');
    final int earnPer = database.settingInt('loyalty_earn_per_minor', 100000);
    final int value = database.settingInt('loyalty_point_value_minor', 100);
    if (!on || earnPer <= 0 || value <= 0) return off;

    return LoyaltyRules(
      enabled: true,
      earnPerMinor: earnPer,
      pointValueMinor: value,
      minRedeemPoints: database.settingInt('loyalty_min_redeem_points', 0),
    );
  }

  final bool enabled;

  /// How much has to be spent to earn one point, in minor units.
  final int earnPerMinor;

  /// What one point takes off a bill, in minor units.
  final int pointValueMinor;

  /// Below this, points cannot be spent — it stops a queue forming over
  /// twenty dinars.
  final int minRedeemPoints;

  /// Points earned by a bill. Deliberately floor, not round: a scheme that
  /// rounds up gives away points nobody spent, and a customer never complains
  /// about the shop being strict with itself.
  int pointsFor(int spentMinor) =>
      !enabled || spentMinor <= 0 ? 0 : spentMinor ~/ earnPerMinor;

  /// What [points] are worth in money.
  int valueOf(int points) => points <= 0 ? 0 : points * pointValueMinor;

  /// The most points that can usefully be spent on a bill of [totalMinor],
  /// given a balance of [balance].
  int redeemableFor({required int balance, required int totalMinor}) {
    if (!enabled || balance < minRedeemPoints || totalMinor <= 0) return 0;
    final int affordable = totalMinor ~/ pointValueMinor;
    final int capped = affordable < balance ? affordable : balance;
    return capped < 0 ? 0 : capped;
  }
}

/// Points earned and spent.
///
/// ## How this is booked, and why
///
/// Points are recorded in their own ledger and **not** as a liability in the
/// journal. Earning changes no money: nothing has been given away until the
/// customer comes back. Redeeming is booked as a tender against a
/// `loyalty_redeemed` expense account — the sale is still a sale at its full
/// price, and what the scheme cost the shop appears on the income statement as
/// its own line, where an owner can see whether it is worth running.
///
/// The alternative — accruing a liability as points are earned — is the
/// treatment a large chain uses, and it would put an estimate of future
/// redemptions into a small shop's books every single sale. This is the
/// simpler truth: the cost is recognised when it is actually incurred.
class LoyaltyService {
  const LoyaltyService._();

  /// What a customer has, right now.
  static Future<int> balance(DatabaseExecutor db, int partyId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT IFNULL(SUM(points), 0) AS n FROM loyalty_ledger WHERE party_id = ?',
      <Object?>[partyId],
    );
    return rows.first['n'] as int? ?? 0;
  }

  /// Records points earned by a sale. Returns what was given.
  static Future<int> earn(
    DatabaseExecutor db, {
    required int? partyId,
    required int spentMinor,
    required LoyaltyRules rules,
    int? docId,
    int? userId,
    String docType = 'sale',
  }) async {
    if (partyId == null || !rules.enabled) return 0;
    final int points = rules.pointsFor(spentMinor);
    if (points <= 0) return 0;

    await db.insert('loyalty_ledger', <String, Object?>{
      'party_id': partyId,
      'happened_at': Time.stamp(),
      'points': points,
      'kind': 'earn',
      'doc_type': docType,
      'doc_id': docId,
      'user_id': userId,
    });
    return points;
  }

  /// Records points being spent, refusing to spend more than there are.
  static Future<int> redeem(
    DatabaseExecutor db, {
    required int partyId,
    required int points,
    required LoyaltyRules rules,
    int? docId,
    int? userId,
    String docType = 'sale',
  }) async {
    if (points <= 0) return 0;
    if (!rules.enabled) {
      throw const AppFailure.validation('The points scheme is switched off.');
    }

    final int have = await balance(db, partyId);
    if (points > have) {
      throw AppFailure.validation(
        'That customer has $have points, not $points.',
      );
    }
    if (have < rules.minRedeemPoints) {
      throw AppFailure.validation(
        'Points can be used from ${rules.minRedeemPoints} up.',
      );
    }

    await db.insert('loyalty_ledger', <String, Object?>{
      'party_id': partyId,
      'happened_at': Time.stamp(),
      'points': -points,
      'kind': 'redeem',
      'doc_type': docType,
      'doc_id': docId,
      'user_id': userId,
    });
    return points;
  }

  /// Takes back the points a cancelled sale gave and returns the ones it took,
  /// so voiding an invoice leaves the customer exactly where they started.
  static Future<void> reverseForSale(
    DatabaseExecutor db, {
    required int invoiceId,
    int? userId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'loyalty_ledger',
      where: "doc_type = 'sale' AND doc_id = ? AND kind IN ('earn','redeem')",
      whereArgs: <Object?>[invoiceId],
    );
    if (rows.isEmpty) return;

    final String stamp = Time.stamp();
    for (final Map<String, Object?> r in rows) {
      await db.insert('loyalty_ledger', <String, Object?>{
        'party_id': r['party_id'],
        'happened_at': stamp,
        'points': -(r['points'] as int? ?? 0),
        'kind': 'adjust',
        'doc_type': 'sale_void',
        'doc_id': invoiceId,
        'user_id': userId,
        'note': 'Reversal of ${r['kind']}',
      });
    }
  }

  /// A manual correction — a goodwill gesture, or fixing a mistake.
  static Future<void> adjust(
    DatabaseExecutor db, {
    required int partyId,
    required int points,
    String? note,
    int? userId,
  }) async {
    if (points == 0) return;
    await db.insert('loyalty_ledger', <String, Object?>{
      'party_id': partyId,
      'happened_at': Time.stamp(),
      'points': points,
      'kind': 'adjust',
      'user_id': userId,
      'note': note,
    });
  }

  /// Rounds a redemption to whole points that fit the bill exactly, so the
  /// customer is never left owing four dinars because their points did not
  /// divide evenly.
  static int pointsToCover(int amountMinor, LoyaltyRules rules) =>
      rules.pointValueMinor <= 0
          ? 0
          : divRound(amountMinor, rules.pointValueMinor);
}
