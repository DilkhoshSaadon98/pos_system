import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/money/fx.dart';
import '../../../../core/money/money.dart';
import '../../../../core/shifts/shift_service.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/shift.dart';

/// Reading and writing drawers.
///
/// The arithmetic and the postings live in [ShiftService]; this file is the
/// database's side of it — queries for the screen, and one transaction around
/// each write so a count can never be half-recorded.
class ShiftsLocalDataSource {
  const ShiftsLocalDataSource(this._database);

  final AppDatabase _database;

  FxRate get fx => FxRate.fromSettings(_database);

  bool get shiftsRequired => _database.settingBool('shifts_required', true);

  /// The drawer this cashier has open, if any.
  Future<CashShift?> current({int? userId}) async {
    final int? id = await ShiftService.openShiftId(_database.db, userId: userId);
    if (id == null) return null;
    return byId(id);
  }

  Future<CashShift> byId(int shiftId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_shift_totals',
      where: 'shift_id = ?',
      whereArgs: <Object?>[shiftId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AppFailure.notFound('That shift no longer exists.');
    }
    return CashShift.fromRow(rows.first);
  }

  /// Shifts in a date range, newest first.
  Future<List<CashShift>> list({
    required DateTime from,
    required DateTime to,
    int? userId,
  }) async {
    final StringBuffer where = StringBuffer('opened_at BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[
      Time.startOfDay(from),
      Time.endOfDay(to),
    ];
    if (userId != null) {
      where.write(' AND user_id = ?');
      args.add(userId);
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_shift_totals',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'opened_at DESC',
    );
    return rows.map(CashShift.fromRow).toList(growable: false);
  }

  /// Opens a drawer with a counted float.
  Future<CashShift> open({
    required int floatMinor,
    int floatFxMinor = 0,
    int? userId,
    String? note,
  }) async {
    final FxRate rate = fx;
    final int id = await _database.transaction((Transaction txn) async {
      final int shiftId = await ShiftService.open(
        txn,
        userId: userId,
        floatMinor: floatMinor,
        floatFxMinor: floatFxMinor,
        fx: rate,
        note: note,
      );
      await Audit.write(
        txn,
        action: Audit.shiftOpen,
        entity: 'cash_shift',
        entityId: shiftId,
        userId: userId,
        shiftId: shiftId,
        detail: 'float $floatMinor'
            '${floatFxMinor > 0 ? ' + ${rate.format(floatFxMinor)}' : ''}',
      );
      return shiftId;
    });
    return byId(id);
  }

  /// Counts the drawer and closes it. Returns the Z report.
  Future<ShiftReport> close(ShiftCloseRequest request) async {
    final FxRate rate = fx;
    await _database.transaction((Transaction txn) async {
      final ShiftReconciliation result = await ShiftService.close(
        txn,
        shiftId: request.shiftId,
        countedMinor: request.countedMinor,
        countedFxMinor: request.countedFxMinor,
        fx: rate,
        userId: request.userId,
        note: request.note,
      );
      await Audit.write(
        txn,
        action: Audit.shiftClose,
        entity: 'cash_shift',
        entityId: request.shiftId,
        userId: request.userId,
        shiftId: request.shiftId,
        detail: 'counted ${result.countedMinor}, expected '
            '${result.expectedMinor}, difference ${result.differenceMinor}',
      );
    });
    return report(request.shiftId);
  }

  /// The X report while the drawer is open, the Z report once it is closed.
  Future<ShiftReport> report(int shiftId) async {
    final CashShift shift = await byId(shiftId);

    final List<Map<String, Object?>> tenderRows = await _database.db.query(
      'v_shift_tenders',
      where: 'shift_id = ?',
      whereArgs: <Object?>[shiftId],
      orderBy: 'direction DESC, method',
    );

    final FxRate rate = fx;
    final int expected = shift.isOpen
        ? await ShiftService.expectedCash(_database.db)
        : (shift.expected?.minor ?? 0);

    final int expectedFx = shift.isOpen
        ? await ShiftService.expectedForeignCash(
            _database.db,
            shiftId: shiftId,
            openingFxMinor: shift.openingFloatFxMinor,
            fxCode: rate.code,
          )
        : (shift.countedFxMinor ?? 0);

    return ShiftReport(
      shift: shift,
      tenders: tenderRows.map(ShiftTenderRow.fromRow).toList(growable: false),
      expected: Money(expected),
      expectedFxMinor: expectedFx,
      generatedAt: Time.stamp(),
      isFinal: !shift.isOpen,
    );
  }
}
