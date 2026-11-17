import 'package:dartz/dartz.dart';

import '../../../../core/error/guard.dart';
import '../entities/app_user.dart';

abstract class AuthRepository {
  bool get loginRequired;

  Future<Result<AppUser?>> defaultUser();

  Future<Result<AppUser>> signIn(String username, String password);

  Future<Result<Unit>> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  });
}
