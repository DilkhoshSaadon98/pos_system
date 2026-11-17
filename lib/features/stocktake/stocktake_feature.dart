import 'package:dartz/dartz.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/accounting/account_keys.dart';
import '../../core/accounting/journal.dart';
import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/guard.dart';
import '../../core/inventory/stock_service.dart';
import '../../core/money/money.dart';
import '../../core/utils/audit.dart';
import '../../core/utils/time.dart';

/// A counting session.
class StockCount {
  const StockCount({
    required this.id,
    required this.countNo,
    required this.startedAt,
    required this.status,
    required this.scope,
    required this.varianceValue,
    required this.lineCount,
    required this.countedCount,
    this.finishedAt,
    this.categoryId,
    this.categoryName,
    this.userName,
    this.note,
  });

  factory StockCount.fromRow(Map<String, Object?> m) => StockCount(
        id: m['id'] as int,
        countNo: '${m['count_no']}',
        startedAt: '${m['started_at']}',
        finishedAt: m['finished_at'] as String?,
        status: '${m['status']}',
        scope: '${m['scope']}',
        categoryId: m['category_id'] as int?,
        categoryName: m['category_name'] as String?,
        userName: m['user_name'] as String?,
        varianceValue: Money.fromDb(m['variance_value_minor']),
        lineCount: m['line_count'] as int? ?? 0,
        countedCount: m['counted_count'] as int? ?? 0,
        note: m['note'] as String?,
      );

  final int id;
  final String countNo;
  final String startedAt;
  final String? finishedAt;

  /// `open`, `posted` or `cancelled`.
  final String status;
  final String scope;
  final int? categoryId;
  final String? categoryName;
  final String? userName;

  /// What the differences were worth, once posted.
  final Money varianceValue;

  final int lineCount;
  final int countedCount;
  final String? note;

  bool get isOpen => status == 'open';
  bool get isPosted => status == 'posted';

  /// How much of the sheet has been filled in.
  int get progressBp => lineCount == 0 ? 0 : (countedCount * 10000) ~/ lineCount;
}

/// One item on the sheet.
class StockCountLine {
  const StockCountLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.systemQtyMilli,
    required this.unitCost,
    this.countedQtyMilli,
    this.sku,
    this.unitName = '',
    this.note,
  });

  factory StockCountLine.fromRow(Map<String, Object?> m) => StockCountLine(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name'] ?? ''}',
        sku: m['sku'] as String?,
        unitName: '${m['unit_name'] ?? ''}',
        systemQtyMilli: m['system_qty_milli'] as int? ?? 0,
        countedQtyMilli: m['counted_qty_milli'] as int?,
        unitCost: Money.fromDb(m['unit_cost_minor']),
        note: m['note'] as String?,
      );

  final int id;
  final int itemId;
  final String itemName;
  final String? sku;
  final String unitName;

  /// What the system believed when the sheet was made — frozen, so the person
  /// who counted is judged against what they were actually told.
  final int systemQtyMilli;

  /// Null until somebody counts it.
  final int? countedQtyMilli;

  final Money unitCost;
  final String? note;

  bool get isCounted => countedQtyMilli != null;

  int get varianceMilli =>
      countedQtyMilli == null ? 0 : countedQtyMilli! - systemQtyMilli;

  Money get varianceValue =>
      Money((varianceMilli * unitCost.minor) ~/ 1000);
}

/// Counting the shelves.
///
/// ## Why a session rather than fifty adjustments
///
/// Counting a shop takes a morning. Done as individual adjustments, each item
/// posts its own journal entry the moment it is typed, the shop keeps selling
/// underneath, and by lunchtime nobody can say what the count actually found.
///
/// A session freezes what the system believed for every line at the moment the
/// sheet was made, collects the counts at whatever pace suits, and then posts
/// **once**: one journal entry, one stock movement per item that differed, one
/// number for what the whole exercise found. The variance a manager signs off
/// is the variance the counter faced.
class StocktakeLocalDataSource {
  const StocktakeLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<StockCount>> sessions({int limit = 50}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT s.*, c.name AS category_name, u.full_name AS user_name,
             (SELECT COUNT(*) FROM stock_count_lines l WHERE l.count_id = s.id)
               AS line_count,
             (SELECT COUNT(*) FROM stock_count_lines l
               WHERE l.count_id = s.id AND l.counted_qty_milli IS NOT NULL)
               AS counted_count
        FROM stock_counts s
        LEFT JOIN categories c ON c.id = s.category_id
        LEFT JOIN users u      ON u.id = s.user_id
       ORDER BY s.started_at DESC
       LIMIT ?
      ''',
      <Object?>[limit],
    );
    return rows.map(StockCount.fromRow).toList(growable: false);
  }

  Future<List<StockCountLine>> lines(int countId, {bool onlyUncounted = false}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_stock_count_lines',
      where: onlyUncounted
          ? 'count_id = ? AND counted_qty_milli IS NULL'
          : 'count_id = ?',
      whereArgs: <Object?>[countId],
      orderBy: 'item_name',
    );
    return rows.map(StockCountLine.fromRow).toList(growable: false);
  }

  /// Starts a session and takes the snapshot.
  Future<int> start({
    int? categoryId,
    List<int>? itemIds,
    int? userId,
    String? note,
  }) async {
    return _database.transaction<int>((Transaction txn) async {
      final String stamp = Time.stamp();
      final String countNo =
          await AppDatabase.nextDocumentNumber(txn, 'stock_count');

      final String scope = itemIds != null && itemIds.isNotEmpty
          ? 'selection'
          : (categoryId != null ? 'category' : 'all');

      final int countId = await txn.insert('stock_counts', <String, Object?>{
        'count_no': countNo,
        'started_at': stamp,
        'user_id': userId,
        'category_id': categoryId,
        'scope': scope,
        'status': 'open',
        'note': note,
        'created_at': stamp,
        'updated_at': stamp,
      });

      // Only things that are actually counted on a shelf: a service has
      // nothing to count, a bundle's stock lives in its parts, and a group is
      // never stocked itself.
      final StringBuffer where = StringBuffer(
        "is_active = 1 AND track_stock = 1 AND kind = 'stock'",
      );
      final List<Object?> args = <Object?>[];
      if (scope == 'category') {
        where.write(' AND category_id = ?');
        args.add(categoryId);
      } else if (scope == 'selection') {
        where.write(' AND id IN (${List<String>.filled(itemIds!.length, '?').join(',')})');
        args.addAll(itemIds);
      }

      final List<Map<String, Object?>> items = await txn.query(
        'items',
        columns: <String>['id', 'stock_qty_milli', 'avg_cost_minor'],
        where: where.toString(),
        whereArgs: args,
        orderBy: 'name',
      );
      if (items.isEmpty) {
        throw const AppFailure.validation(
          'There is nothing to count in that selection.',
        );
      }

      int lineNo = 0;
      for (final Map<String, Object?> item in items) {
        await txn.insert('stock_count_lines', <String, Object?>{
          'count_id': countId,
          'item_id': item['id'],
          'system_qty_milli': item['stock_qty_milli'] as int? ?? 0,
          'unit_cost_minor': item['avg_cost_minor'] as int? ?? 0,
          'line_no': lineNo++,
        });
      }

      await Audit.write(
        txn,
        action: 'count_start',
        entity: 'stock_count',
        entityId: countId,
        userId: userId,
        detail: '$countNo · ${items.length} items',
      );

      return countId;
    });
  }

  /// Records what was on the shelf for one line. Passing null clears it back
  /// to "not counted", which is what a counter needs when they lose their place.
  Future<void> setCounted({
    required int lineId,
    int? countedQtyMilli,
    int? userId,
    String? note,
  }) async {
    await _database.db.update(
      'stock_count_lines',
      <String, Object?>{
        'counted_qty_milli': countedQtyMilli,
        'counted_at': countedQtyMilli == null ? null : Time.stamp(),
        'counted_by': countedQtyMilli == null ? null : userId,
        if (note != null) 'note': note,
      },
      where: 'id = ?',
      whereArgs: <Object?>[lineId],
    );
  }

  /// Posts the session: one movement per item that differed, one journal entry
  /// for the lot.
  ///
  /// Lines nobody counted are left alone rather than treated as zero. "We did
  /// not get to the back shelf" must never write the back shelf off.
  Future<Money> post(int countId, {int? userId, bool isOpening = false}) async {
    return _database.transaction<Money>((Transaction txn) async {
      final List<Map<String, Object?>> head = await txn.query(
        'stock_counts',
        where: 'id = ?',
        whereArgs: <Object?>[countId],
        limit: 1,
      );
      if (head.isEmpty) {
        throw const AppFailure.notFound('That count no longer exists.');
      }
      if ('${head.first['status']}' != 'open') {
        throw const AppFailure.conflict('That count has already been posted.');
      }

      final List<Map<String, Object?>> lines = await txn.query(
        'stock_count_lines',
        where: 'count_id = ? AND counted_qty_milli IS NOT NULL',
        whereArgs: <Object?>[countId],
      );
      if (lines.isEmpty) {
        throw const AppFailure.validation(
          'Nothing on this sheet has been counted yet.',
        );
      }

      final String stamp = Time.stamp();
      int totalValue = 0;
      int changed = 0;

      for (final Map<String, Object?> line in lines) {
        final int itemId = line['item_id'] as int;
        final int counted = line['counted_qty_milli'] as int;

        final StockAdjustment adj = await StockService.setCountedQuantity(
          txn,
          itemId: itemId,
          countedBaseMilli: counted,
          userId: userId,
          note: 'Stocktake ${head.first['count_no']}',
        );
        if (adj.valueMinor == 0 && adj.qtyMilli == 0) continue;

        totalValue += adj.valueMinor;
        changed++;
      }

      int? entryId;
      if (totalValue != 0) {
        final int inventory =
            await AppDatabase.accountIdIn(txn, AccountKeys.inventory);
        final int counter = await AppDatabase.accountIdIn(
          txn,
          isOpening ? AccountKeys.openingEquity : AccountKeys.shrinkage,
        );

        entryId = await Journal.post(
          txn,
          sourceType: isOpening ? 'opening' : 'adjustment',
          sourceId: countId,
          entryDate: stamp.substring(0, 10),
          memo: 'Stocktake ${head.first['count_no']}',
          userId: userId,
          lines: totalValue > 0
              // More on the shelf than the books knew: stock goes up, and the
              // gain lands where the losses land, so the two net off over a
              // year instead of flattering one and hiding the other.
              ? <JournalLine>[
                  JournalLine.debit(inventory, totalValue),
                  JournalLine.credit(counter, totalValue),
                ]
              : <JournalLine>[
                  JournalLine.debit(counter, -totalValue),
                  JournalLine.credit(inventory, -totalValue),
                ],
        );
      }

      await txn.update(
        'stock_counts',
        <String, Object?>{
          'status': 'posted',
          'finished_at': stamp,
          'variance_value_minor': totalValue,
          'journal_entry_id': entryId,
          'updated_at': stamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[countId],
      );

      await Audit.write(
        txn,
        action: 'count_post',
        entity: 'stock_count',
        entityId: countId,
        userId: userId,
        detail: '$changed items differed · $totalValue',
      );

      return Money(totalValue);
    });
  }

  Future<void> cancel(int countId, {int? userId}) async {
    await _database.db.update(
      'stock_counts',
      <String, Object?>{'status': 'cancelled', 'updated_at': Time.stamp()},
      where: 'id = ? AND status = ?',
      whereArgs: <Object?>[countId, 'open'],
    );
    await Audit.write(
      _database.db,
      action: 'count_cancel',
      entity: 'stock_count',
      entityId: countId,
      userId: userId,
    );
  }
}

abstract class StocktakeRepository {
  Future<Result<List<StockCount>>> sessions();
  Future<Result<List<StockCountLine>>> lines(int countId);
  Future<Result<int>> start({
    int? categoryId,
    List<int>? itemIds,
    int? userId,
    String? note,
  });
  Future<Result<Unit>> setCounted({
    required int lineId,
    int? countedQtyMilli,
    int? userId,
  });
  Future<Result<Money>> post(int countId, {int? userId});
  Future<Result<Unit>> cancel(int countId, {int? userId});
}

class StocktakeRepositoryImpl implements StocktakeRepository {
  const StocktakeRepositoryImpl(this._local);

  final StocktakeLocalDataSource _local;

  @override
  Future<Result<List<StockCount>>> sessions() => guard(_local.sessions);

  @override
  Future<Result<List<StockCountLine>>> lines(int countId) =>
      guard(() => _local.lines(countId));

  @override
  Future<Result<int>> start({
    int? categoryId,
    List<int>? itemIds,
    int? userId,
    String? note,
  }) =>
      guard(() => _local.start(
            categoryId: categoryId,
            itemIds: itemIds,
            userId: userId,
            note: note,
          ));

  @override
  Future<Result<Unit>> setCounted({
    required int lineId,
    int? countedQtyMilli,
    int? userId,
  }) =>
      guardVoid(() => _local.setCounted(
            lineId: lineId,
            countedQtyMilli: countedQtyMilli,
            userId: userId,
          ));

  @override
  Future<Result<Money>> post(int countId, {int? userId}) =>
      guard(() => _local.post(countId, userId: userId));

  @override
  Future<Result<Unit>> cancel(int countId, {int? userId}) =>
      guardVoid(() => _local.cancel(countId, userId: userId));
}

void initStocktakeInjection() {
  sl.registerLazySingleton<StocktakeLocalDataSource>(
    () => StocktakeLocalDataSource(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<StocktakeRepository>(
    () => StocktakeRepositoryImpl(sl<StocktakeLocalDataSource>()),
  );
}
