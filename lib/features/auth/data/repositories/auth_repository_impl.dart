import 'package:dartz/dartz.dart';

import '../../../../core/error/guard.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._local);

  final AuthLocalDataSource _local;

  @override
  bool get loginRequired => _local.loginRequired;

  @override
  Future<Result<AppUser?>> defaultUser() => guard(_local.defaultUser);

  @override
  Future<Result<AppUser>> signIn(String username, String password) =>
      guard(() => _local.signIn(username, password));

  @override
  Future<Result<Unit>> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) =>
      guardVoid(() => _local.changeOwnPassword(
            userId: userId,
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));
}
