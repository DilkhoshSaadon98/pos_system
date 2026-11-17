import '../../../../core/error/failures.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardState {
  DashboardState({
    this.status = AppStatus.initial,
    DashboardSnapshot? snapshot,
    DateTime? day,
    this.failure,
  })  : snapshot = snapshot ?? DashboardSnapshot.empty,
        day = day ?? DateTime.now();

  final AppStatus status;
  final DashboardSnapshot snapshot;
  final DateTime day;
  final Failure? failure;

  DashboardState copyWith({
    AppStatus? status,
    DashboardSnapshot? snapshot,
    DateTime? day,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      DashboardState(
        status: status ?? this.status,
        snapshot: snapshot ?? this.snapshot,
        day: day ?? this.day,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}