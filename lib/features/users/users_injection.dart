import 'package:dartz/dartz.dart';

import '../../core/classes/enums.dart';
import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import '../auth/domain/entities/app_user.dart';
import 'data/datasources/users_local_datasource.dart';

abstract class UsersRepository {
  Future<Result<List<AppUser>>> all({bool includeInactive = true});

  Future<Result<int>> save({
    int? id,
    required String fullName,
    required String username,
    required UserRole role,
    String? password,
    String? phone,
    bool isActive = true,
  });

  Future<Result<Unit>> remove(int id, {required int? currentUserId});

  Future<Result<Unit>> setPassword(int id, String password);
}

class UsersRepositoryImpl implements UsersRepository {
  const UsersRepositoryImpl(this._local);

  final UsersLocalDataSource _local;

  @override
  Future<Result<List<AppUser>>> all({bool includeInactive = true}) =>
      guard(() => _local.all(includeInactive: includeInactive));

  @override
  Future<Result<int>> save({
    int? id,
    required String fullName,
    required String username,
    required UserRole role,
    String? password,
    String? phone,
    bool isActive = true,
  }) =>
      guard(() => _local.save(
            id: id,
            fullName: fullName,
            username: username,
            role: role,
            password: password,
            phone: phone,
            isActive: isActive,
          ));

  @override
  Future<Result<Unit>> remove(int id, {required int? currentUserId}) =>
      guardVoid(() => _local.remove(id, currentUserId: currentUserId));

  @override
  Future<Result<Unit>> setPassword(int id, String password) =>
      guardVoid(() => _local.setPassword(id, password));
}

void initUsersInjection() {
  sl.registerLazySingleton<UsersLocalDataSource>(
    () => UsersLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<UsersRepository>(
    () => UsersRepositoryImpl(sl<UsersLocalDataSource>()),
  );
}
