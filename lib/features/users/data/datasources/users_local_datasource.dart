import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/security.dart';
import '../../../../core/utils/time.dart';
import '../../../auth/domain/entities/app_user.dart';

/// Who may use this till, and what each of them may do.
class UsersLocalDataSource {
  UsersLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<AppUser>> all({bool includeInactive = true}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'users',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'is_active DESC, full_name COLLATE NOCASE',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  /// Creates or updates a user. A blank password on an edit means "leave it
  /// alone" — the alternative is a shopkeeper accidentally resetting a
  /// cashier's password every time they fix a typo in a name.
  Future<int> save({
    int? id,
    required String fullName,
    required String username,
    required UserRole role,
    String? password,
    String? phone,
    bool isActive = true,
  }) async {
    final String name = fullName.trim();
    final String login = username.trim();

    if (name.isEmpty) {
      throw const AppFailure.validation('The user needs a name.');
    }
    if (login.isEmpty) {
      throw const AppFailure.validation('The user needs a username.');
    }
    if (id == null && (password ?? '').isEmpty) {
      throw const AppFailure.validation('Give the new user a password.');
    }
    if ((password ?? '').isNotEmpty && password!.length < 4) {
      throw const AppFailure.validation('Use at least four characters.');
    }

    return _database.transaction<int>((Transaction txn) async {
      // A shop must always be able to get back in. Losing the last owner —
      // by demoting them or by hiding them — locks everyone out of the users
      // screen with no way back short of editing the database file.
      if (id != null) {
        await _guardLastOwner(txn, id, role, isActive);
      }

      final String stamp = Time.stamp();
      final Map<String, Object?> values = <String, Object?>{
        'full_name': name,
        'username': login,
        'role': role.dbValue,
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'is_active': isActive ? 1 : 0,
        'updated_at': stamp,
      };

      if ((password ?? '').isNotEmpty) {
        final String salt = Security.newSalt();
        values['password_salt'] = salt;
        values['password_hash'] = Security.hashPassword(password!, salt);
      }

      if (id == null) {
        values['created_at'] = stamp;
        final int newId = await txn.insert('users', values);
        await Audit.write(
          txn,
          action: Audit.userSave,
          entity: 'user',
          entityId: newId,
          detail: '$username · ${role.dbValue}',
        );
        return newId;
      }
      await txn.update('users', values,
          where: 'id = ?', whereArgs: <Object?>[id]);
      await Audit.write(
        txn,
        action: Audit.userSave,
        entity: 'user',
        entityId: id,
        detail: '$username · ${role.dbValue}',
      );
      return id;
    });
  }

  Future<void> remove(int id, {required int? currentUserId}) async {
    if (id == currentUserId) {
      throw const AppFailure.validation(
        'You cannot remove the account you are using.',
      );
    }

    await _database.transaction<void>((Transaction txn) async {
      await _guardLastOwner(txn, id, null, false);

      // A user who has rung up a sale is referenced by every invoice they
      // touched. Those references are what makes "who sold this" answerable, so
      // the account is hidden rather than deleted.
      final List<Map<String, Object?>> used = await txn.rawQuery(
        '''
        SELECT (SELECT COUNT(*) FROM sales_invoices    WHERE user_id = ?) AS sales,
               (SELECT COUNT(*) FROM purchase_invoices WHERE user_id = ?) AS buys,
               (SELECT COUNT(*) FROM journal_entries   WHERE user_id = ?) AS entries
        ''',
        <Object?>[id, id, id],
      );
      final Map<String, Object?> c = used.first;
      final bool hasHistory = (c['sales'] as int) > 0 ||
          (c['buys'] as int) > 0 ||
          (c['entries'] as int) > 0;

      if (hasHistory) {
        await txn.update(
          'users',
          <String, Object?>{'is_active': 0, 'updated_at': Time.stamp()},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        return;
      }
      await txn.delete('users', where: 'id = ?', whereArgs: <Object?>[id]);
      await Audit.write(
        txn,
        action: Audit.userRemove,
        entity: 'user',
        entityId: id,
        userId: currentUserId,
      );
    });
  }

  Future<void> setPassword(int id, String password) async {
    if (password.length < 4) {
      throw const AppFailure.validation('Use at least four characters.');
    }
    final String salt = Security.newSalt();
    await _database.db.update(
      'users',
      <String, Object?>{
        'password_salt': salt,
        'password_hash': Security.hashPassword(password, salt),
        'updated_at': Time.stamp(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    await Audit.write(
      _database.db,
      action: Audit.passwordSet,
      entity: 'user',
      entityId: id,
    );
  }

  /// Refuses a change that would leave no active owner.
  Future<void> _guardLastOwner(
    DatabaseExecutor txn,
    int id,
    UserRole? newRole,
    bool stillActive,
  ) async {
    final List<Map<String, Object?>> rows = await txn.query(
      'users',
      columns: <String>['role', 'is_active'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final bool wasActiveOwner = '${rows.first['role']}' == 'owner' &&
        (rows.first['is_active'] as int? ?? 0) == 1;
    if (!wasActiveOwner) return;

    final bool staysOwner =
        (newRole ?? UserRole.cashier) == UserRole.owner && stillActive;
    if (staysOwner) return;

    final List<Map<String, Object?>> owners = await txn.rawQuery(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'owner' AND is_active = 1",
    );
    if ((owners.first['n'] as int? ?? 0) <= 1) {
      throw const AppFailure.conflict(
        'There has to be one active owner. Make somebody else the owner first.',
      );
    }
  }
}
