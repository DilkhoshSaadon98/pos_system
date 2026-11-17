import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/security.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/app_user.dart';


class AuthLocalDataSource {
  AuthLocalDataSource(this._database);

  final AppDatabase _database;

  bool get loginRequired => _database.settingBool('require_login', true);

  Future<AppUser?> defaultUser() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'users',
      where: 'is_active = 1',
      orderBy: 'id',
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<AppUser> signIn(String username, String password) async {
    final String name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      throw const AppFailure.validation('Enter a username and a password.');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'users',
      where: 'username = ? COLLATE NOCASE AND is_active = 1',
      whereArgs: <Object?>[name],
      limit: 1,
    );

    const AppFailure wrong =
        AppFailure.permission('Wrong username or password.');
    if (rows.isEmpty) throw wrong;

    final Map<String, Object?> row = rows.first;
    final bool ok = Security.verifyPassword(
      password,
      '${row['password_salt']}',
      '${row['password_hash']}',
    );
    if (!ok) throw wrong;

    await _database.db.update(
      'users',
      <String, Object?>{'last_login_at': Time.stamp()},
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );


    await _database.setSessionUser(row['id'] as int?);

    await Audit.write(
      _database.db,
      action: Audit.signIn,
      entity: 'user',
      entityId: row['id'] as int?,
      userId: row['id'] as int?,
      detail: '$name',
    );

    return AppUser.fromMap(row);
  }

  Future<void> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 4) {
      throw const AppFailure.validation('Use at least four characters.');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'users',
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AppFailure.notFound('That user no longer exists.');
    }
    final bool ok = Security.verifyPassword(
      currentPassword,
      '${rows.first['password_salt']}',
      '${rows.first['password_hash']}',
    );
    if (!ok) {
      throw const AppFailure.permission('The current password is wrong.');
    }

    final String salt = Security.newSalt();
    await _database.db.update(
      'users',
      <String, Object?>{
        'password_salt': salt,
        'password_hash': Security.hashPassword(newPassword, salt),
        'updated_at': Time.stamp(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
  }
}
