import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import '../../core/money/fx.dart';
import 'data/datasources/shifts_local_datasource.dart';
import 'domain/entities/shift.dart';

/// What the drawer offers the rest of the app.
abstract class ShiftsRepository {
  /// True when a cashier must open a drawer before the till will sell.
  bool get shiftsRequired;

  /// The shop's second currency as it stands right now.
  FxRate get fx;

  Future<Result<CashShift?>> current({int? userId});

  Future<Result<CashShift>> open({
    required int floatMinor,
    int floatFxMinor,
    int? userId,
    String? note,
  });

  Future<Result<ShiftReport>> close(ShiftCloseRequest request);

  /// The X report while the drawer is open; the Z report once it is closed.
  Future<Result<ShiftReport>> report(int shiftId);

  Future<Result<List<CashShift>>> list({
    required DateTime from,
    required DateTime to,
    int? userId,
  });
}

class ShiftsRepositoryImpl implements ShiftsRepository {
  const ShiftsRepositoryImpl(this._local);

  final ShiftsLocalDataSource _local;

  @override
  bool get shiftsRequired => _local.shiftsRequired;

  @override
  FxRate get fx => _local.fx;

  @override
  Future<Result<CashShift?>> current({int? userId}) =>
      guard(() => _local.current(userId: userId));

  @override
  Future<Result<CashShift>> open({
    required int floatMinor,
    int floatFxMinor = 0,
    int? userId,
    String? note,
  }) =>
      guard(() => _local.open(
            floatMinor: floatMinor,
            floatFxMinor: floatFxMinor,
            userId: userId,
            note: note,
          ));

  @override
  Future<Result<ShiftReport>> close(ShiftCloseRequest request) =>
      guard(() => _local.close(request));

  @override
  Future<Result<ShiftReport>> report(int shiftId) =>
      guard(() => _local.report(shiftId));

  @override
  Future<Result<List<CashShift>>> list({
    required DateTime from,
    required DateTime to,
    int? userId,
  }) =>
      guard(() => _local.list(from: from, to: to, userId: userId));
}

void initShiftsInjection() {
  sl.registerLazySingleton<ShiftsLocalDataSource>(
    () => ShiftsLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<ShiftsRepository>(
    () => ShiftsRepositoryImpl(sl<ShiftsLocalDataSource>()),
  );
}
