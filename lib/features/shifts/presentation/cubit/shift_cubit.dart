import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/fx.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/shift.dart';
import '../../shifts_injection.dart';

class ShiftState {
  const ShiftState({
    this.status = AppStatus.initial,
    this.current,
    this.history = const <CashShift>[],
    this.report,
    this.busy = false,
    this.failure,
    this.from,
    this.to,
  });

  final AppStatus status;

  /// The drawer this cashier has open, or null when there is none.
  final CashShift? current;

  final List<CashShift> history;

  /// The report being looked at — X for an open drawer, Z for a closed one.
  final ShiftReport? report;

  final bool busy;
  final Failure? failure;
  final DateTime? from;
  final DateTime? to;

  bool get hasOpenShift => current != null;

  ShiftState copyWith({
    AppStatus? status,
    CashShift? current,
    bool clearCurrent = false,
    List<CashShift>? history,
    ShiftReport? report,
    bool clearReport = false,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    DateTime? from,
    DateTime? to,
  }) =>
      ShiftState(
        status: status ?? this.status,
        current: clearCurrent ? null : (current ?? this.current),
        history: history ?? this.history,
        report: clearReport ? null : (report ?? this.report),
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
        from: from ?? this.from,
        to: to ?? this.to,
      );
}

/// The drawer, as the screen sees it.
class ShiftCubit extends Cubit<ShiftState> {
  ShiftCubit(this._repository, {int? userId})
      : _userId = userId,
        super(const ShiftState());

  final ShiftsRepository _repository;
  final int? _userId;

  FxRate get fx => _repository.fx;
  bool get shiftsRequired => _repository.shiftsRequired;

  Future<void> load({DateTime? from, DateTime? to}) async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final DateTime start =
        from ?? state.from ?? DateTime.now().subtract(const Duration(days: 14));
    final DateTime end = to ?? state.to ?? DateTime.now();

    final Result<CashShift?> open = await _repository.current(userId: _userId);
    final Result<List<CashShift>> history =
        await _repository.list(from: start, to: end);
    if (isClosed) return;

    final Failure? failure = firstFailure(<Result<Object?>>[open, history]);
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    final CashShift? currentShift = open.valueOrNull;
    emit(ShiftState(
      status: AppStatus.ready,
      current: currentShift,
      history: history.valueOr(const <CashShift>[]),
      from: start,
      to: end,
    ));

    if (currentShift != null) await showReport(currentShift.id);
  }

  /// Opens a drawer with a counted float.
  Future<bool> open({
    required int floatMinor,
    int floatFxMinor = 0,
    String? note,
  }) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<CashShift> result = await _repository.open(
      floatMinor: floatMinor,
      floatFxMinor: floatFxMinor,
      userId: _userId,
      note: note,
    );
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }

    emit(state.copyWith(busy: false, current: result.valueOrNull));
    await load();
    return true;
  }

  /// Counts the drawer and closes it, leaving the Z report on screen.
  Future<ShiftReport?> closeShift({
    required int countedMinor,
    int countedFxMinor = 0,
    String? note,
  }) async {
    final CashShift? shift = state.current;
    if (shift == null) return null;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<ShiftReport> result = await _repository.close(
      ShiftCloseRequest(
        shiftId: shift.id,
        countedMinor: countedMinor,
        countedFxMinor: countedFxMinor,
        userId: _userId,
        note: note,
      ),
    );
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }

    final ShiftReport report = result.valueOrNull!;
    emit(state.copyWith(busy: false, clearCurrent: true, report: report));
    await load();
    if (!isClosed) emit(state.copyWith(report: report));
    return report;
  }

  /// The X report, taken without touching anything.
  Future<void> showReport(int shiftId) async {
    final Result<ShiftReport> result = await _repository.report(shiftId);
    if (isClosed) return;
    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(failure: failure)
        : state.copyWith(report: result.valueOrNull));
  }

  void clearReport() => emit(state.copyWith(clearReport: true));

  void clearFailure() => emit(state.copyWith(clearFailure: true));

  Future<void> setRange(DateTime from, DateTime to) =>
      load(from: from, to: to);
}
