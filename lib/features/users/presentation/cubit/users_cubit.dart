import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../users_injection.dart';

class UsersState {
  const UsersState({
    this.status = AppStatus.initial,
    this.users = const <AppUser>[],
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<AppUser> users;
  final bool busy;
  final Failure? failure;

  int get activeOwners => users
      .where((AppUser u) => u.role == UserRole.owner && u.isActive)
      .length;

  UsersState copyWith({
    AppStatus? status,
    List<AppUser>? users,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      UsersState(
        status: status ?? this.status,
        users: users ?? this.users,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class UsersCubit extends Cubit<UsersState> {
  UsersCubit(this._repository) : super(const UsersState());

  final UsersRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));
    final Result<List<AppUser>> result = await _repository.all();
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            users: result.valueOrNull,
            clearFailure: true,
          ));
  }

  Future<bool> save({
    int? id,
    required String fullName,
    required String username,
    required UserRole role,
    String? password,
    String? phone,
    bool isActive = true,
  }) =>
      _write(() => _repository.save(
            id: id,
            fullName: fullName,
            username: username,
            role: role,
            password: password,
            phone: phone,
            isActive: isActive,
          ));

  Future<bool> remove(int id, {required int? currentUserId}) =>
      _write(() => _repository.remove(id, currentUserId: currentUserId));

  Future<bool> setPassword(int id, String password) =>
      _write(() => _repository.setPassword(id, password));

  void clearFailure() => emit(state.copyWith(clearFailure: true));

  Future<bool> _write<T>(Future<Result<T>> Function() action) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<T> result = await action();
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }
    await load();
    if (!isClosed) emit(state.copyWith(busy: false));
    return true;
  }
}
