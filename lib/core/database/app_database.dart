import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/time.dart';
import 'migrations/m001_schema.dart';
import 'migrations/m002_seed.dart';
import 'migrations/m003_item_types.dart';
import 'migrations/m004_shifts_fx.dart';
import 'migrations/m005_operations.dart';
import 'migrations/m006_history.dart';


final class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const String fileName = 'cashier_v2.db';

  // ! NEVER modify previous migration versions; increment version only for schema changes.
  static const int schemaVersion = 5;

  static const Map<int, List<String>> _migrations = {
    2: schemaV2,
    3: schemaV3,
    4: schemaV4,
    5: schemaV5,
  };

  Database? _db;
  final Map<String, String> _settingsCache = {};
  final Map<String, int> _accountCache = {};

  // ! Throws StateError if called before awaiting open().
  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDatabase.open() must be awaited before use.');
    }
    return d;
  }

  //? Checks whether database connection is active.
  static bool get isOpen => instance._db != null;

  //? Determines platform database factory (FFI for Desktop, Native for Mobile).
  static DatabaseFactory platformFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  //* Configures PRAGMA settings (foreign_keys=ON, journal_mode=WAL).
  Future<Database> open({String? overridePath}) async {
    if (_db != null) return _db!;

    final factory = platformFactory();
    final path = overridePath ?? await defaultPath();
    await Directory(p.dirname(path)).create(recursive: true);

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _createSchema(db);
          await seedInitialData(db);
          await _backfillV2Settings(db);
          await _backfillV3(db);
          await _backfillV4(db);
          await _backfillV5(db);
        },
        onUpgrade: (db, from, to) async =>
            runMigrations(db, from: from, to: to),
        onOpen: (db) async {
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        },
      ),
    );
    return _db!;
  }

  //? Returns application local directory storage path.
  Future<String> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, fileName);
  }

  // ? Foreign keys are temporarily disabled during execution for safety.
  static Future<void> runMigrations(
    Database db, {
    required int from,
    required int to,
  }) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      for (int v = from + 1; v <= to; v++) {
        final statements = _migrations[v];
        if (statements == null) continue;
        await db.transaction((txn) async {
          for (final s in statements) {
            await txn.execute(s);
          }
        });

        if (v == 2) await _backfillV2Settings(db);
        if (v == 3) await _backfillV3(db);
        if (v == 4) await _backfillV4(db);
        if (v == 5) await _backfillV5(db);

        await db.insert(
          'app_meta',
          {'key': 'schema_version', 'value': '$v'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // ** Migration Backfill Helpers (V2 - V5)
  static Future<void> _backfillV2Settings(DatabaseExecutor db) async {
    final stamp = Time.stamp();
    for (final e in settingsV2.entries) {
      await db.insert(
        'settings',
        {'key': e.key, 'value': e.value, 'updated_at': stamp},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _backfillV3(DatabaseExecutor db) async {
    final stamp = Time.stamp();
    for (final e in settingsV3.entries) {
      await db.insert(
        'settings',
        {'key': e.key, 'value': e.value, 'updated_at': stamp},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    for (final e in accountsV3.entries) {
      final existing = await db.query(
        'accounts',
        columns: ['id'],
        where: 'system_key = ?',
        whereArgs: [e.key],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;

      final a = e.value;
      final parent = await db.query(
        'accounts',
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [a[6]],
        limit: 1,
      );

      await db.insert('accounts', {
        'code': a[0],
        'name': a[1],
        'name_ar': a[2],
        'name_ku': a[3],
        'type': a[4],
        'normal_side': a[5],
        'parent_id': parent.isEmpty ? null : parent.first['id'],
        'system_key': e.key,
        'is_group': 0,
        'is_active': 1,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  }

  static Future<void> _backfillV4(DatabaseExecutor db) async {
    final stamp = Time.stamp();
    for (final e in settingsV4.entries) {
      await db.insert(
        'settings',
        {'key': e.key, 'value': e.value, 'updated_at': stamp},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    for (final e in accountsV4.entries) {
      final existing = await db.query(
        'accounts',
        columns: ['id'],
        where: 'system_key = ?',
        whereArgs: [e.key],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;

      final a = e.value;
      final parent = await db.query(
        'accounts',
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [a[6]],
        limit: 1,
      );

      await db.insert('accounts', {
        'code': a[0],
        'name': a[1],
        'name_ar': a[2],
        'name_ku': a[3],
        'type': a[4],
        'normal_side': a[5],
        'parent_id': parent.isEmpty ? null : parent.first['id'],
        'system_key': e.key,
        'is_group': 0,
        'is_active': 1,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }

    const roles = ['manager', 'cashier', 'accountant'];
    for (final e in defaultPermissions.entries) {
      for (final role in roles) {
        await db.insert(
          'role_permissions',
          {
            'role': role,
            'permission': e.key,
            'allowed': e.value.contains(role) ? 1 : 0,
            'updated_at': stamp,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await db.insert(
        'role_permissions',
        {
          'role': 'owner',
          'permission': e.key,
          'allowed': 1,
          'updated_at': stamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _backfillV5(DatabaseExecutor db) async {
    final stamp = Time.stamp();
    for (final e in settingsV5.entries) {
      await db.insert(
        'settings',
        {'key': e.key, 'value': e.value, 'updated_at': stamp},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    const roles = ['manager', 'cashier', 'accountant'];
    for (final e in permissionsV5.entries) {
      for (final role in roles) {
        await db.insert(
          'role_permissions',
          {
            'role': role,
            'permission': e.key,
            'allowed': e.value.contains(role) ? 1 : 0,
            'updated_at': stamp,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await db.insert(
        'role_permissions',
        {
          'role': 'owner',
          'permission': e.key,
          'allowed': 1,
          'updated_at': stamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Saves the active authenticated user ID into session table.
  Future<void> setSessionUser(int? userId) async {
    await db.update(
      'app_session',
      {'user_id': userId, 'since': Time.stamp()},
      where: 'id = 1',
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    final schemas = [schemaV1, schemaV2, schemaV3, schemaV4, schemaV5];
    for (final schema in schemas) {
      for (final statement in schema) {
        await db.execute(statement);
      }
    }
    await db.insert('app_meta', {
      'key': 'schema_version',
      'value': '$schemaVersion',
    });
  }

  //? Builds total database structure and seeds defaults for imported databases.
  static Future<void> createSchemaAndSeed(DatabaseExecutor db) async {
    await _createSchema(db);
    await seedInitialData(db);
    await _backfillV2Settings(db);
    await _backfillV3(db);
    await _backfillV4(db);
    await _backfillV5(db);
  }

  //? Runs custom database callback block within an isolated transaction.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      db.transaction<T>(action);

  //? Closes database connection safely.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ** Settings Management & Cache
  Map<String, String> get settingsSnapshot =>
      Map<String, String>.unmodifiable(_settingsCache);

  /// Caches system settings in-memory for instant lookup.
  Future<void> loadSettings() async {
    final rows = await db.query('settings');
    _settingsCache
      ..clear()
      ..addEntries(rows.map(
        (r) => MapEntry('${r['key']}', '${r['value'] ?? ''}'),
      ));
  }

  /// Resolves setting string value by [key] with [fallback].
  String settingString(String key, [String fallback = '']) {
    final v = _settingsCache[key];
    return (v == null || v.isEmpty) ? fallback : v;
  }

  /// Resolves setting integer value by [key] with [fallback].
  int settingInt(String key, [int fallback = 0]) =>
      int.tryParse(_settingsCache[key] ?? '') ?? fallback;

  /// Resolves setting boolean value by [key] with [fallback].
  bool settingBool(String key, [bool fallback = false]) {
    final v = _settingsCache[key];
    if (v == null || v.isEmpty) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  /// Updates or inserts a single key-value setting.
  Future<void> setSetting(String key, String value) async {
    await db.insert(
      'settings',
      {'key': key, 'value': value, 'updated_at': Time.stamp()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _settingsCache[key] = value;
  }

  /// Batch updates key-value settings within a single transaction.
  Future<void> setSettings(Map<String, String> values) async {
    await db.transaction((txn) async {
      final stamp = Time.stamp();
      for (final e in values.entries) {
        await txn.insert(
          'settings',
          {'key': e.key, 'value': e.value, 'updated_at': stamp},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _settingsCache.addAll(values);
  }

  //? Returns auto-incremented document formatted sequence string (e.g. `INV-2026-000173`).
  static Future<String> nextDocumentNumber(
    DatabaseExecutor db,
    String name, {
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final rows = await db.query(
      'counters',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (rows.isEmpty) {
      final prefix = name.toUpperCase().substring(0, 3);
      await db.insert('counters', {
        'name': name,
        'prefix': prefix,
        'period': 'year',
        'last_value': 1,
      });
      return '$prefix-${when.year}-000001';
    }

    final row = rows.first;
    final next = (row['last_value'] as int? ?? 0) + 1;
    await db.update(
      'counters',
      {'last_value': next},
      where: 'name = ?',
      whereArgs: [name],
    );

    final prefix = '${row['prefix'] ?? ''}';
    final period = '${row['period'] ?? ''}';
    final middle = period == 'year' ? '-${when.year}' : '';
    return '$prefix$middle-${next.toString().padLeft(6, '0')}';
  }

  // ** Financial Accounts Directory Lookup
  //? Resolves account database ID by [systemKey] with internal caching.
  Future<int> accountId(String systemKey) async {
    final cached = _accountCache[systemKey];
    if (cached != null) return cached;
    final id = await accountIdIn(db, systemKey);
    _accountCache[systemKey] = id;
    return id;
  }

  //? Clears in-memory accounts lookup cache.
  void forgetAccountCache() => _accountCache.clear();

  //! Throws StateError if system key does not exist.
  static Future<int> accountIdIn(
    DatabaseExecutor db,
    String systemKey,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'system_key = ?',
      whereArgs: [systemKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No account carries the system key "$systemKey".');
    }
    return rows.first['id'] as int;
  }
}
