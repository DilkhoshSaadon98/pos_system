import 'package:dartz/dartz.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/calc/promotions.dart';
import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/guard.dart';
import '../../core/loyalty/loyalty_service.dart';
import '../../core/utils/audit.dart';
import '../../core/utils/time.dart';

/// A promotion as the editing screen holds it: the rule, plus the items it
/// applies to.
class PromotionDraft {
  const PromotionDraft({
    this.id,
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
    this.isActive = true,
    this.itemIds = const <int>[],
  });

  final int? id;
  final String name;
  final PromotionKind kind;
  final int valueBp;
  final int valueMinor;
  final int minQtyMilli;
  final int getQtyMilli;
  final String scope;
  final int? categoryId;
  final String? startsOn;
  final String? endsOn;
  final String weekdays;
  final String priceMode;
  final bool membersOnly;
  final int priority;
  final bool isActive;
  final List<int> itemIds;
}

/// Offers, and the points scheme.
///
/// The two live together because they are the same question from a shop's
/// point of view — *what am I giving away, and is it working?* — and because
/// both are read by the till at the start of a shift and rarely after.
class PromotionsLocalDataSource {
  const PromotionsLocalDataSource(this._database);

  final AppDatabase _database;

  LoyaltyRules get loyaltyRules => LoyaltyRules.fromSettings(_database);

  /// Every offer that could apply today, with its item list attached.
  ///
  /// Read once when the till opens rather than per line: a basket of twenty
  /// items would otherwise ask the database twenty times for a list that
  /// changes twice a month.
  Future<List<Promotion>> activeToday() async {
    final List<Map<String, Object?>> rows =
        await _database.db.query('v_active_promotions', orderBy: 'priority DESC, id');
    if (rows.isEmpty) return const <Promotion>[];

    final List<Map<String, Object?>> links =
        await _database.db.query('promotion_items');
    final Map<int, Set<int>> byPromotion = <int, Set<int>>{};
    for (final Map<String, Object?> l in links) {
      byPromotion
          .putIfAbsent(l['promotion_id'] as int, () => <int>{})
          .add(l['item_id'] as int);
    }

    return rows
        .map((Map<String, Object?> r) => Promotion.fromRow(
              r,
              itemIds: byPromotion[r['id'] as int] ?? const <int>{},
            ))
        .toList(growable: false);
  }

  /// All of them, for the screen that edits them.
  Future<List<Map<String, Object?>>> all() => _database.db.rawQuery('''
      SELECT p.*, c.name AS category_name,
             (SELECT COUNT(*) FROM promotion_items pi WHERE pi.promotion_id = p.id)
               AS item_count
        FROM promotions p
        LEFT JOIN categories c ON c.id = p.category_id
       ORDER BY p.is_active DESC, p.priority DESC, p.name
      ''');

  Future<List<int>> itemsOf(int promotionId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'promotion_items',
      columns: <String>['item_id'],
      where: 'promotion_id = ?',
      whereArgs: <Object?>[promotionId],
    );
    return rows.map((Map<String, Object?> r) => r['item_id'] as int).toList();
  }

  Future<int> save(PromotionDraft draft, {int? userId}) async {
    _validate(draft);

    return _database.transaction<int>((Transaction txn) async {
      final String stamp = Time.stamp();
      final Map<String, Object?> values = <String, Object?>{
        'name': draft.name.trim(),
        'kind': draft.kind.dbValue,
        'value_bp': draft.valueBp,
        'value_minor': draft.valueMinor,
        'min_qty_milli': draft.minQtyMilli,
        'get_qty_milli': draft.getQtyMilli,
        'scope': draft.scope,
        'category_id': draft.scope == 'category' ? draft.categoryId : null,
        'starts_on': draft.startsOn,
        'ends_on': draft.endsOn,
        'weekdays': draft.weekdays,
        'price_mode': draft.priceMode,
        'members_only': draft.membersOnly ? 1 : 0,
        'priority': draft.priority,
        'is_active': draft.isActive ? 1 : 0,
        'updated_at': stamp,
      };

      int id;
      if (draft.id == null) {
        values['created_at'] = stamp;
        id = await txn.insert('promotions', values);
      } else {
        id = draft.id!;
        await txn.update('promotions', values,
            where: 'id = ?', whereArgs: <Object?>[id]);
        await txn.delete('promotion_items',
            where: 'promotion_id = ?', whereArgs: <Object?>[id]);
      }

      if (draft.scope == 'items') {
        for (final int itemId in draft.itemIds.toSet()) {
          await txn.insert('promotion_items', <String, Object?>{
            'promotion_id': id,
            'item_id': itemId,
          });
        }
      }

      await Audit.write(
        txn,
        action: 'promotion_save',
        entity: 'promotion',
        entityId: id,
        userId: userId,
        detail: '${draft.name} · ${draft.kind.dbValue}',
      );

      return id;
    });
  }

  Future<void> setActive(int id, bool active, {int? userId}) async {
    await _database.db.update(
      'promotions',
      <String, Object?>{'is_active': active ? 1 : 0, 'updated_at': Time.stamp()},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    await Audit.write(
      _database.db,
      action: 'promotion_save',
      entity: 'promotion',
      entityId: id,
      userId: userId,
      detail: active ? 'on' : 'off',
    );
  }

  Future<void> remove(int id, {int? userId}) async {
    // An offer that priced a sale is referenced by that invoice line, and the
    // reference is what lets a receipt be explained a year later. Deleting is
    // therefore only allowed while nothing has used it.
    final List<Map<String, Object?>> used = await _database.db.rawQuery(
      'SELECT COUNT(*) AS n FROM sales_invoice_lines WHERE promotion_id = ?',
      <Object?>[id],
    );
    if ((used.first['n'] as int? ?? 0) > 0) {
      throw const AppFailure.conflict(
        'This offer has already priced sales, so it cannot be deleted. Switch '
        'it off instead — the old receipts keep their explanation.',
      );
    }

    await _database.db.delete('promotions', where: 'id = ?', whereArgs: <Object?>[id]);
    await Audit.write(
      _database.db,
      action: 'promotion_save',
      entity: 'promotion',
      entityId: id,
      userId: userId,
      detail: 'deleted',
    );
  }

  /// What each offer has actually cost and sold, so a shop can tell a good
  /// offer from an expensive habit.
  Future<List<Map<String, Object?>>> performance({int days = 90}) {
    return _database.db.rawQuery('''
      SELECT p.id, p.name, p.kind,
             COUNT(l.id)                                   AS lines_sold,
             IFNULL(SUM(l.qty_base_milli), 0)              AS qty_milli,
             IFNULL(SUM(l.line_discount_minor
                        + l.alloc_discount_minor), 0)      AS given_minor,
             IFNULL(SUM(l.net_minor), 0)                   AS revenue_minor,
             IFNULL(SUM(l.net_minor - l.cost_minor), 0)    AS profit_minor
        FROM promotions p
        LEFT JOIN sales_invoice_lines l ON l.promotion_id = p.id
        LEFT JOIN sales_invoices v ON v.id = l.invoice_id
             AND v.status <> 'void'
             AND v.issued_at >= datetime('now', ?)
       GROUP BY p.id
       ORDER BY given_minor DESC
      ''', <Object?>['-$days day']);
  }

  /// Customers and what they have collected.
  Future<List<Map<String, Object?>>> loyaltyBalances({int limit = 200}) {
    return _database.db.query(
      'v_loyalty_balances',
      where: 'points <> 0',
      orderBy: 'points DESC',
      limit: limit,
    );
  }

  Future<int> pointsOf(int partyId) =>
      LoyaltyService.balance(_database.db, partyId);

  Future<void> adjustPoints({
    required int partyId,
    required int points,
    String? note,
    int? userId,
  }) =>
      LoyaltyService.adjust(
        _database.db,
        partyId: partyId,
        points: points,
        note: note,
        userId: userId,
      );

  void _validate(PromotionDraft d) {
    if (d.name.trim().isEmpty) {
      throw const AppFailure.validation('Give the offer a name.');
    }
    switch (d.kind) {
      case PromotionKind.percent:
        if (d.valueBp <= 0 || d.valueBp > 10000) {
          throw const AppFailure.validation(
            'A percentage offer needs a figure between 0 and 100.',
          );
        }
      case PromotionKind.amount:
      case PromotionKind.price:
        if (d.valueMinor <= 0) {
          throw const AppFailure.validation('Set the amount for this offer.');
        }
      case PromotionKind.quantity:
        if (d.minQtyMilli <= 0 || d.valueMinor <= 0) {
          throw const AppFailure.validation(
            'A quantity offer needs both how many, and the price from there up.',
          );
        }
      case PromotionKind.buyGet:
        if (d.minQtyMilli <= 0 || d.getQtyMilli <= 0) {
          throw const AppFailure.validation(
            'Set how many are bought and how many are free.',
          );
        }
    }
    if (d.scope == 'items' && d.itemIds.isEmpty) {
      throw const AppFailure.validation('Choose the items this offer applies to.');
    }
    if (d.scope == 'category' && d.categoryId == null) {
      throw const AppFailure.validation('Choose the category.');
    }
    if ((d.startsOn ?? '').isNotEmpty &&
        (d.endsOn ?? '').isNotEmpty &&
        d.endsOn!.compareTo(d.startsOn!) < 0) {
      throw const AppFailure.validation('The offer ends before it starts.');
    }
  }
}

abstract class PromotionsRepository {
  LoyaltyRules get loyaltyRules;
  Future<Result<List<Promotion>>> activeToday();
  Future<Result<List<Map<String, Object?>>>> all();
  Future<Result<List<int>>> itemsOf(int promotionId);
  Future<Result<int>> save(PromotionDraft draft, {int? userId});
  Future<Result<Unit>> setActive(int id, bool active, {int? userId});
  Future<Result<Unit>> remove(int id, {int? userId});
  Future<Result<List<Map<String, Object?>>>> performance();
  Future<Result<List<Map<String, Object?>>>> loyaltyBalances();
  Future<Result<int>> pointsOf(int partyId);
  Future<Result<Unit>> adjustPoints({
    required int partyId,
    required int points,
    String? note,
    int? userId,
  });
}

class PromotionsRepositoryImpl implements PromotionsRepository {
  const PromotionsRepositoryImpl(this._local);

  final PromotionsLocalDataSource _local;

  @override
  LoyaltyRules get loyaltyRules => _local.loyaltyRules;

  @override
  Future<Result<List<Promotion>>> activeToday() => guard(_local.activeToday);

  @override
  Future<Result<List<Map<String, Object?>>>> all() => guard(_local.all);

  @override
  Future<Result<List<int>>> itemsOf(int promotionId) =>
      guard(() => _local.itemsOf(promotionId));

  @override
  Future<Result<int>> save(PromotionDraft draft, {int? userId}) =>
      guard(() => _local.save(draft, userId: userId));

  @override
  Future<Result<Unit>> setActive(int id, bool active, {int? userId}) =>
      guardVoid(() => _local.setActive(id, active, userId: userId));

  @override
  Future<Result<Unit>> remove(int id, {int? userId}) =>
      guardVoid(() => _local.remove(id, userId: userId));

  @override
  Future<Result<List<Map<String, Object?>>>> performance() =>
      guard(_local.performance);

  @override
  Future<Result<List<Map<String, Object?>>>> loyaltyBalances() =>
      guard(_local.loyaltyBalances);

  @override
  Future<Result<int>> pointsOf(int partyId) =>
      guard(() => _local.pointsOf(partyId));

  @override
  Future<Result<Unit>> adjustPoints({
    required int partyId,
    required int points,
    String? note,
    int? userId,
  }) =>
      guardVoid(() => _local.adjustPoints(
            partyId: partyId,
            points: points,
            note: note,
            userId: userId,
          ));
}

void initPromotionsInjection() {
  sl.registerLazySingleton<PromotionsLocalDataSource>(
    () => PromotionsLocalDataSource(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<PromotionsRepository>(
    () => PromotionsRepositoryImpl(sl<PromotionsLocalDataSource>()),
  );
}
