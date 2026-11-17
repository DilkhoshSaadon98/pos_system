import 'package:sqflite_common/sqlite_api.dart';

import '../error/exceptions.dart';
import '../utils/time.dart';

/// One batch, as the picker sees it.
class BatchPick {
  const BatchPick({
    required this.batchId,
    required this.qtyMilli,
    this.batchNo = '',
    this.expiryDate,
  });

  final int batchId;
  final int qtyMilli;
  final String batchNo;
  final String? expiryDate;
}

/// Which physical box the goods came out of.
///
/// ## What this is, and what it deliberately is not
///
/// A batch answers *how many, from which delivery, expiring when*. It does
/// **not** value anything: the cost of a sale is still the item's moving
/// average, computed by `StockService`, exactly as it was before batches
/// existed. Keeping the two apart is what lets a shop gain expiry control
/// without the meaning of a single figure in the ledger changing.
///
/// ## FEFO, not FIFO
///
/// Stock leaves in **first-expiry-first-out** order, not the order it arrived.
/// They are usually the same, and when they differ — a delivery arrives with a
/// shorter date than what is already on the shelf — the shorter date has to go
/// first or it will be thrown away. A batch with no date at all is used last,
/// because it can wait and a dated one cannot.
class BatchService {
  const BatchService._();

  /// Finds or creates the batch a delivery belongs to.
  ///
  /// Two deliveries of the same lot number and date are one batch: the shelf
  /// has one pile, and splitting it in the database would only make the expiry
  /// report harder to read.
  static Future<int> upsert(
    DatabaseExecutor db, {
    required int itemId,
    String batchNo = '',
    String? expiryDate,
    String? productionDate,
    int unitCostMinor = 0,
    int? partyId,
    String? docType,
    int? docId,
    String? receivedAt,
    String? note,
  }) async {
    final String stamp = receivedAt ?? Time.stamp();

    final List<Map<String, Object?>> existing = await db.query(
      'item_batches',
      columns: <String>['id'],
      where: "item_id = ? AND batch_no = ? AND IFNULL(expiry_date, '') = ?",
      whereArgs: <Object?>[itemId, batchNo, expiryDate ?? ''],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final int id = existing.first['id'] as int;
      await db.update(
        'item_batches',
        <String, Object?>{
          // The newest arrival's cost is the one worth showing next to the box.
          if (unitCostMinor > 0) 'unit_cost_minor': unitCostMinor,
          if (partyId != null) 'party_id': partyId,
          'is_active': 1,
          'updated_at': stamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return id;
    }

    return db.insert('item_batches', <String, Object?>{
      'item_id': itemId,
      'batch_no': batchNo,
      'expiry_date': expiryDate,
      'production_date': productionDate,
      'qty_milli': 0,
      'unit_cost_minor': unitCostMinor,
      'party_id': partyId,
      'received_at': stamp,
      'doc_type': docType,
      'doc_id': docId,
      'note': note,
      'is_active': 1,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  /// Whether this item is counted by batch at all.
  static Future<bool> tracksBatches(DatabaseExecutor db, int itemId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'items',
      columns: <String>['track_batches'],
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
      limit: 1,
    );
    return rows.isNotEmpty && (rows.first['track_batches'] as int? ?? 0) == 1;
  }

  /// Splits [qtyBaseMilli] across the batches on the shelf, soonest expiry
  /// first.
  ///
  /// Returns the picks in the order they should be taken. When the shelf holds
  /// less than was asked for — which happens when an item is sold before its
  /// delivery is entered — the shortfall comes out of the **last** pick rather
  /// than failing: refusing the sale would be worse than a batch record that
  /// goes momentarily negative, and `StockService` already decides separately
  /// whether negative stock is allowed at all.
  static Future<List<BatchPick>> pickFefo(
    DatabaseExecutor db, {
    required int itemId,
    required int qtyBaseMilli,
  }) async {
    if (qtyBaseMilli <= 0) return const <BatchPick>[];

    final List<Map<String, Object?>> rows = await db.query(
      'item_batches',
      where: 'item_id = ? AND is_active = 1 AND qty_milli > 0',
      whereArgs: <Object?>[itemId],
      // Dated batches first, soonest date first; undated ones last, because
      // they are the only ones that can wait.
      orderBy: "CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, "
          'expiry_date ASC, received_at ASC, id ASC',
    );
    if (rows.isEmpty) return const <BatchPick>[];

    final List<BatchPick> picks = <BatchPick>[];
    int left = qtyBaseMilli;

    for (final Map<String, Object?> r in rows) {
      if (left <= 0) break;
      final int have = r['qty_milli'] as int? ?? 0;
      final int take = have < left ? have : left;
      if (take <= 0) continue;

      picks.add(BatchPick(
        batchId: r['id'] as int,
        qtyMilli: take,
        batchNo: '${r['batch_no'] ?? ''}',
        expiryDate: r['expiry_date'] as String?,
      ));
      left -= take;
    }

    if (left > 0 && picks.isNotEmpty) {
      // Everything on the shelf, plus the shortfall, on the oldest pick.
      final BatchPick last = picks.last;
      picks[picks.length - 1] = BatchPick(
        batchId: last.batchId,
        qtyMilli: last.qtyMilli + left,
        batchNo: last.batchNo,
        expiryDate: last.expiryDate,
      );
    }

    return picks;
  }

  /// The batch a sale should take from when only one is needed — the shortest
  /// date with enough on it, or simply the shortest date.
  static Future<int?> nextBatchId(
    DatabaseExecutor db, {
    required int itemId,
    required int qtyBaseMilli,
  }) async {
    final List<BatchPick> picks =
        await pickFefo(db, itemId: itemId, qtyBaseMilli: qtyBaseMilli);
    return picks.isEmpty ? null : picks.first.batchId;
  }

  /// Batches on the shelf that expire within [days], soonest first.
  static Future<List<Map<String, Object?>>> expiring(
    DatabaseExecutor db, {
    int days = 30,
    bool includeExpired = true,
  }) {
    return db.rawQuery(
      '''
      SELECT * FROM v_batch_stock
       WHERE expiry_date IS NOT NULL
         AND days_left <= ?
         ${includeExpired ? '' : 'AND days_left >= 0'}
       ORDER BY expiry_date ASC, item_name ASC
      ''',
      <Object?>[days],
    );
  }

  /// Refuses a date that has already passed on goods being *received*.
  ///
  /// Selling expired stock is a decision a shop can make; buying it into
  /// inventory as if it were good is almost always a typo in the date.
  static void guardReceivedExpiry(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty) return;
    final DateTime? parsed = DateTime.tryParse(expiryDate);
    if (parsed == null) return;
    if (parsed.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw const AppFailure.validation(
        'That expiry date has already passed. Check the date on the box — '
        'goods cannot be received as expired.',
      );
    }
  }
}
