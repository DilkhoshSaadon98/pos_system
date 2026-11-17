import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/security/permissions.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthState {
  const AuthState({
    this.status = AppStatus.initial,
    this.user,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final AppUser? user;
  final bool busy;
  final Failure? failure;

  bool get isSignedIn => user != null;

  AuthState copyWith({
    AppStatus? status,
    AppUser? user,
    bool clearUser = false,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}


class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState());

  final AuthRepository _repository;

  Future<void> bootstrap() async {
    emit(state.copyWith(status: AppStatus.loading));

    if (_repository.loginRequired) {
      emit(state.copyWith(status: AppStatus.ready, clearUser: true));
      return;
    }

    final Result<AppUser?> result = await _repository.defaultUser();
    if (isClosed) return;

    await _loadPermissions();
    if (isClosed) return;

    emit(state.copyWith(
      status: AppStatus.ready,
      user: result.valueOrNull,
      failure: result.failureOrNull,
    ));
  }

  Future<void> _loadPermissions() async {
    try {
      await Permissions.load(sl<AppDatabase>());
    } catch (_) {
    }
  }

  Future<bool> signIn(String username, String password) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<AppUser> result = await _repository.signIn(username, password);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }
    await _loadPermissions();
    if (isClosed) return false;

    emit(state.copyWith(
      busy: false,
      status: AppStatus.ready,
      user: result.valueOrNull,
      clearFailure: true,
    ));
    return true;
  }

  void signOut() {
    unawaited(sl<AppDatabase>().setSessionUser(null));
    emit(state.copyWith(clearUser: true, clearFailure: true));
  }

  Future<bool> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final AppUser? user = state.user;
    if (user == null) return false;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result = await _repository.changeOwnPassword(
      userId: user.id,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    return failure == null;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
