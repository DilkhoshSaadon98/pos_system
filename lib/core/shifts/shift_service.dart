import 'package:sqflite_common/sqlite_api.dart';

import '../accounting/account_keys.dart';
import '../accounting/journal.dart';
import '../database/app_database.dart';
import '../error/exceptions.dart';
import '../money/fx.dart';
import '../utils/time.dart';

/// What a count found, and what the books had to say about it.
class ShiftReconciliation {
  const ShiftReconciliation({
    required this.expectedMinor,
    required this.countedMinor,
    required this.expectedFxMinor,
    required this.countedFxMinor,
    required this.differenceMinor,
    required this.differenceFxMinor,
    required this.fxRevaluationMinor,
    this.journalEntryId,
  });

  /// What the ledger says the drawer holds, in the shop's own currency.
  final int expectedMinor;
  final int countedMinor;

  /// The foreign drawer, in that currency's own minor units.
  final int expectedFxMinor;
  final int countedFxMinor;

  /// `counted − expected`. Negative is a shortage.
  final int differenceMinor;
  final int differenceFxMinor;

  /// The part of the foreign drawer's change in value that is the rate moving
  /// rather than money going missing.
  final int fxRevaluationMinor;

  final int? journalEntryId;

  bool get isClean => differenceMinor == 0 && differenceFxMinor == 0;

  /// The whole discrepancy in the shop's own currency, which is the number a
  /// manager actually looks at.
  int shortfallMinor(FxRate fx) =>
      differenceMinor + fx.toBase(differenceFxMinor);
}

/// Opening, counting and closing the drawer.
///
/// ## Why the count is reconciled to the ledger, not to a running total
///
/// It would be easy to say the drawer *should* hold "the opening float plus
/// everything this shift took in", and to compare the count against that. It
/// would also be wrong the first time somebody paid a supplier out of the till
/// or dropped the takings into the safe without recording it: the running
/// total and the cash account would drift apart, and the books would keep the
/// error forever while every shift reported a clean count.
///
/// So the expected figure here is **the cash account's balance**, and a count
/// that disagrees with it is posted — at the open as well as at the close — to
/// `cash_over_short`. After every count, the ledger and the drawer agree by
/// construction. A shop that is short 2,000 sees it as an expense on the
/// income statement, which is exactly what a shortage is.
///
/// ## The foreign drawer
///
/// Dollars in the till are held in their own account, valued in the shop's
/// currency. Two different things can change that value, and they are not the
/// same event:
///
/// * dollars went missing (or arrived) — a **count difference**, valued at
///   today's rate and posted to `cash_over_short`;
/// * the rate moved since the money was taken — a **revaluation**, posted to
///   `fx_difference`, which is a fact about the currency and not about the
///   cashier.
///
/// The close separates them; the open cannot (there is no expectation to
/// compare against yet), so at the open the whole movement is treated as
/// revaluation.
class ShiftService {
  const ShiftService._();

  /// The open shift for [userId], or null when there is none.
  ///
  /// With no user — a background job, an import — the single open shift is
  /// returned if exactly one exists, and null if the shop has several tills
  /// open, because guessing which drawer to charge would be worse than not
  /// tagging the entry at all.
  static Future<int?> openShiftId(DatabaseExecutor db, {int? userId}) async {
    final List<Map<String, Object?>> rows = await db.query(
      'cash_shifts',
      columns: <String>['id'],
      where: userId == null ? "status = 'open'" : "status = 'open' AND user_id = ?",
      whereArgs: userId == null ? null : <Object?>[userId],
      orderBy: 'opened_at DESC',
      limit: 2,
    );
    if (rows.isEmpty) return null;
    if (userId == null && rows.length > 1) return null;
    return rows.first['id'] as int;
  }

  /// The shift a document being posted right now belongs to.
  ///
  /// Refuses the whole document when the shop requires shifts and this cashier
  /// has not opened one — better than taking the money and having no drawer to
  /// account for it.
  static Future<int?> resolveForPosting(
    DatabaseExecutor db, {
    required bool enforce,
    required int? userId,
  }) async {
    final int? id = await openShiftId(db, userId: userId);
    if (id != null) return id;
    if (!enforce) return null;
    throw const AppFailure.validation(
      'Open a shift before taking money. The drawer has to be counted at the '
      'start so it can be counted at the end.',
    );
  }

  /// Opens a drawer with a counted float.
  ///
  /// Any gap between the count and the cash account is posted immediately, so
  /// the shift starts from a truth both the drawer and the books agree on.
  static Future<int> open(
    DatabaseExecutor db, {
    required int? userId,
    required int floatMinor,
    required FxRate fx,
    int floatFxMinor = 0,
    String? note,
  }) async {
    if (floatMinor < 0 || floatFxMinor < 0) {
      throw const AppFailure.validation('A float cannot be negative.');
    }
    if (await openShiftId(db, userId: userId) != null) {
      throw const AppFailure.validation(
        'This cashier already has a shift open. Close it before opening '
        'another.',
      );
    }

    final String stamp = Time.stamp();
    final String shiftNo = await AppDatabase.nextDocumentNumber(db, 'shift');

    final int shiftId = await db.insert('cash_shifts', <String, Object?>{
      'shift_no': shiftNo,
      'user_id': userId,
      'opened_at': stamp,
      'opening_float_minor': floatMinor,
      'opening_float_fx_minor': floatFxMinor,
      'fx_rate_milli': fx.isUsable ? fx.rateMilli : 0,
      'status': 'open',
      'note': note,
      'created_at': stamp,
      'updated_at': stamp,
    });

    // At the open there is no movement to build an expectation from, so the
    // books' own idea of the drawer is used: what the foreign cash account is
    // worth, converted back at today's rate. Anything the count finds beyond
    // that is a difference like any other.
    await _reconcile(
      db,
      shiftId: shiftId,
      countedMinor: floatMinor,
      countedFxMinor: floatFxMinor,
      expectedFxMinor: null,
      fx: fx,
      userId: userId,
      memo: 'Opening count — $shiftNo',
    );

    return shiftId;
  }

  /// Counts the drawer and closes it.
  ///
  /// Returns what was found so the Z report can print the difference rather
  /// than making the screen work it out a second time.
  static Future<ShiftReconciliation> close(
    DatabaseExecutor db, {
    required int shiftId,
    required int countedMinor,
    required FxRate fx,
    int countedFxMinor = 0,
    int? userId,
    String? note,
  }) async {
    if (countedMinor < 0 || countedFxMinor < 0) {
      throw const AppFailure.validation('A count cannot be negative.');
    }

    final List<Map<String, Object?>> rows = await db.query(
      'cash_shifts',
      where: 'id = ?',
      whereArgs: <Object?>[shiftId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AppFailure.notFound('That shift no longer exists.');
    }
    final Map<String, Object?> shift = rows.first;
    if ('${shift['status']}' != 'open') {
      throw const AppFailure.validation('That shift is already closed.');
    }

    final int expectedFx = await _expectedForeignCash(
      db,
      shiftId: shiftId,
      openingFxMinor: shift['opening_float_fx_minor'] as int? ?? 0,
      fxCode: fx.code,
    );

    final ShiftReconciliation result = await _reconcile(
      db,
      shiftId: shiftId,
      countedMinor: countedMinor,
      countedFxMinor: countedFxMinor,
      expectedFxMinor: expectedFx,
      fx: fx,
      userId: userId,
      memo: 'Closing count — ${shift['shift_no']}',
    );

    final String stamp = Time.stamp();
    await db.update(
      'cash_shifts',
      <String, Object?>{
        'closed_at': stamp,
        'closed_by_user_id': userId,
        'counted_minor': countedMinor,
        'counted_fx_minor': countedFxMinor,
        'expected_minor': result.expectedMinor,
        'expected_fx_minor': result.expectedFxMinor,
        'difference_minor': result.differenceMinor,
        'fx_rate_milli': fx.isUsable ? fx.rateMilli : 0,
        'journal_entry_id': result.journalEntryId,
        'note': note ?? shift['note'],
        'status': 'closed',
        'updated_at': stamp,
      },
      where: 'id = ?',
      whereArgs: <Object?>[shiftId],
    );

    return result;
  }

  /// The foreign cash the drawer should hold, in that currency's minor units:
  /// what it started with, plus what was taken in it, less what was given back.
  static Future<int> _expectedForeignCash(
    DatabaseExecutor db, {
    required int shiftId,
    required int openingFxMinor,
    required String fxCode,
  }) async {
    if (fxCode.isEmpty) return openingFxMinor;

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(CASE WHEN t.direction = 'in' THEN t.amount_fx_minor
                             ELSE -t.amount_fx_minor END), 0) AS net
        FROM sale_tenders t
        JOIN sales_invoices i ON i.id = t.invoice_id
       WHERE i.shift_id = ?
         AND i.status <> 'void'
         AND t.currency_code = ?
      ''',
      <Object?>[shiftId, fxCode],
    );

    final List<Map<String, Object?>> paid = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(CASE WHEN p.kind = 'receipt' THEN p.amount_fx_minor
                             ELSE -p.amount_fx_minor END), 0) AS net
        FROM payments p
       WHERE p.shift_id = ?
         AND p.is_void = 0
         AND p.currency_code = ?
      ''',
      <Object?>[shiftId, fxCode],
    );

    return openingFxMinor +
        (rows.first['net'] as int? ?? 0) +
        (paid.first['net'] as int? ?? 0);
  }

  /// Posts the difference between a count and the books, in both currencies.
  ///
  /// Returns without writing anything when the count agrees with the ledger to
  /// the last unit, because an entry of zero is noise in a journal somebody
  /// has to read.
  static Future<ShiftReconciliation> _reconcile(
    DatabaseExecutor db, {
    required int shiftId,
    required int countedMinor,
    required int countedFxMinor,
    required int? expectedFxMinor,
    required FxRate fx,
    required int? userId,
    required String memo,
  }) async {
    final int cashId = await AppDatabase.accountIdIn(db, AccountKeys.cash);
    final int overShortId =
        await AppDatabase.accountIdIn(db, AccountKeys.cashOverShort);

    final int expected = await _balanceOf(db, AccountKeys.cash);
    final int difference = countedMinor - expected;

    int fxDifferenceUnits = 0;
    int fxCountBase = 0;
    int revaluation = 0;
    int? fxCashId;
    int? fxDiffAccountId;

    if (fx.isUsable) {
      fxCashId = await AppDatabase.accountIdIn(db, AccountKeys.cashForeign);
      fxDiffAccountId =
          await AppDatabase.accountIdIn(db, AccountKeys.fxDifference);

      final int fxLedger = await _balanceOf(db, AccountKeys.cashForeign);
      // With no expectation of its own, the books supply one: what the account
      // holds, converted back at today's rate.
      final int expectedUnits = expectedFxMinor ?? fx.toFx(fxLedger);
      fxDifferenceUnits = countedFxMinor - expectedUnits;
      fxCountBase = fx.toBase(fxDifferenceUnits);

      // After the count adjustment the account must be worth exactly what is
      // in the drawer at today's rate; whatever is left over is the rate
      // having moved, not money having moved.
      final int target = fx.toBase(countedFxMinor);
      revaluation = target - (fxLedger + fxCountBase);
    }

    final List<JournalLine> lines = <JournalLine>[];

    if (difference > 0) {
      // More in the drawer than the books know about.
      lines.add(JournalLine.debit(cashId, difference));
      lines.add(JournalLine.credit(overShortId, difference));
    } else if (difference < 0) {
      lines.add(JournalLine.debit(overShortId, -difference));
      lines.add(JournalLine.credit(cashId, -difference));
    }

    if (fxCashId != null && fxCountBase != 0) {
      if (fxCountBase > 0) {
        lines.add(JournalLine.debit(fxCashId, fxCountBase));
        lines.add(JournalLine.credit(overShortId, fxCountBase));
      } else {
        lines.add(JournalLine.debit(overShortId, -fxCountBase));
        lines.add(JournalLine.credit(fxCashId, -fxCountBase));
      }
    }

    if (fxCashId != null && fxDiffAccountId != null && revaluation != 0) {
      if (revaluation > 0) {
        // The dollars in the drawer are worth more than they were booked at.
        lines.add(JournalLine.debit(fxCashId, revaluation));
        lines.add(JournalLine.credit(fxDiffAccountId, revaluation));
      } else {
        lines.add(JournalLine.debit(fxDiffAccountId, -revaluation));
        lines.add(JournalLine.credit(fxCashId, -revaluation));
      }
    }

    int? entryId;
    if (lines.isNotEmpty) {
      entryId = await Journal.post(
        db,
        sourceType: 'closing',
        sourceId: shiftId,
        memo: memo,
        userId: userId,
        shiftId: shiftId,
        lines: lines,
      );
    }

    return ShiftReconciliation(
      expectedMinor: expected,
      countedMinor: countedMinor,
      expectedFxMinor: countedFxMinor - fxDifferenceUnits,
      countedFxMinor: countedFxMinor,
      differenceMinor: difference,
      differenceFxMinor: fxDifferenceUnits,
      fxRevaluationMinor: revaluation,
      journalEntryId: entryId,
    );
  }

  static Future<int> _balanceOf(DatabaseExecutor db, String systemKey) async {
    final List<Map<String, Object?>> rows = await db.query(
      'v_account_balances',
      columns: <String>['balance_minor'],
      where: 'system_key = ?',
      whereArgs: <Object?>[systemKey],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['balance_minor'] as int? ?? 0);
  }

  /// What the drawer should hold right now — used by the X report, which is
  /// the same count without closing anything.
  static Future<int> expectedCash(DatabaseExecutor db) =>
      _balanceOf(db, AccountKeys.cash);

  /// The foreign drawer's expectation mid-shift, in foreign minor units.
  static Future<int> expectedForeignCash(
    DatabaseExecutor db, {
    required int shiftId,
    required int openingFxMinor,
    required String fxCode,
  }) =>
      _expectedForeignCash(
        db,
        shiftId: shiftId,
        openingFxMinor: openingFxMinor,
        fxCode: fxCode,
      );
}
