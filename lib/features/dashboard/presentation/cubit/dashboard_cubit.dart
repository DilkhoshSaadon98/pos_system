

import 'package:cashier_system_v2/core/error/failures.dart';
import 'package:cashier_system_v2/core/error/guard.dart';
import 'package:cashier_system_v2/core/state/app_status.dart';
import 'package:cashier_system_v2/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:cashier_system_v2/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cashier_system_v2/features/dashboard/presentation/cubit/dashboard_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository) : super(DashboardState());

  final DashboardRepository _repository;

  Future<void> load({DateTime? day}) async {
    emit(state.copyWith(
      status: AppStatus.loading,
      day: day,
      clearFailure: true,
    ));

    final Result<DashboardSnapshot> result =
        await _repository.load(day: day ?? state.day);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            snapshot: result.valueOrNull,
            clearFailure: true,
          ));
  }
}
