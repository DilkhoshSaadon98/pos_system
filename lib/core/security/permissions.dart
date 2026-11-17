import 'package:sqflite_common/sqlite_api.dart';

import '../classes/enums.dart';
import '../database/app_database.dart';
import '../error/exceptions.dart';
import '../utils/time.dart';


class Perm {
  const Perm._();

  static const String posUse = 'pos.use';
  static const String posDiscount = 'pos.discount';
  static const String posBelowMinPrice = 'pos.below_min_price';

  static const String posOverCreditLimit = 'pos.over_credit_limit';
  static const String posVoid = 'pos.void';
  static const String posReturn = 'pos.return';

  static const String itemsView = 'items.view';
  static const String itemsEdit = 'items.edit';

  static const String itemsCost = 'items.cost';

  static const String purchasesView = 'purchases.view';
  static const String purchasesEdit = 'purchases.edit';
  static const String ordersEdit = 'orders.edit';

  static const String stockAdjust = 'stock.adjust';
  static const String stockCount = 'stock.count';

  static const String partiesView = 'parties.view';
  static const String partiesEdit = 'parties.edit';

  static const String reportsView = 'reports.view';
  static const String reportsProfit = 'reports.profit';

  static const String accountingView = 'accounting.view';
  static const String accountingPost = 'accounting.post';

  static const String shiftsCloseOther = 'shifts.close_other';
  static const String promotionsEdit = 'promotions.edit';
  static const String settingsEdit = 'settings.edit';
  static const String usersEdit = 'users.edit';
  static const String auditView = 'audit.view';

  static const List<String> all = <String>[
    posUse,
    posDiscount,
    posBelowMinPrice,
    posOverCreditLimit,
    posVoid,
    posReturn,
    itemsView,
    itemsEdit,
    itemsCost,
    purchasesView,
    purchasesEdit,
    ordersEdit,
    stockAdjust,
    stockCount,
    partiesView,
    partiesEdit,
    reportsView,
    reportsProfit,
    accountingView,
    accountingPost,
    shiftsCloseOther,
    promotionsEdit,
    settingsEdit,
    usersEdit,
    auditView,
  ];
}

class Permissions {
  Permissions._();

  static final Permissions instance = Permissions._();

  final Map<String, Set<String>> _allowed = <String, Set<String>>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> reload(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'role_permissions',
      where: 'allowed = 1',
    );
    _allowed
      ..clear()
      ..addEntries(<MapEntry<String, Set<String>>>[
        for (final String role in <String>[
          'owner',
          'manager',
          'cashier',
          'accountant'
        ])
          MapEntry<String, Set<String>>(role, <String>{}),
      ]);
    for (final Map<String, Object?> r in rows) {
      _allowed
          .putIfAbsent('${r['role']}', () => <String>{})
          .add('${r['permission']}');
    }
    _loaded = true;
  }


  bool can(UserRole? role, String permission) {
    if (role == null) return false;
    if (role == UserRole.owner) return true;
    if (!_loaded) return false;
    return _allowed[role.dbValue]?.contains(permission) ?? false;
  }

  void require(UserRole? role, String permission, {String? what}) {
    if (can(role, permission)) return;
    throw AppFailure.permission(
      what == null
          ? 'Your account is not allowed to do that.'
          : 'Your account is not allowed to $what.',
    );
  }

  Set<String> forRole(UserRole role) => role == UserRole.owner
      ? Perm.all.toSet()
      : (_allowed[role.dbValue] ?? <String>{});

  static Future<void> set(
    DatabaseExecutor db, {
    required UserRole role,
    required String permission,
    required bool allowed,
  }) async {
    if (role == UserRole.owner) {
      throw const AppFailure.validation(
        'The owner keeps every permission — that is what makes them the owner.',
      );
    }

    await db.insert(
      'role_permissions',
      <String, Object?>{
        'role': role.dbValue,
        'permission': permission,
        'allowed': allowed ? 1 : 0,
        'updated_at': Time.stamp(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> load(AppDatabase database) =>
      instance.reload(database.db);
}
