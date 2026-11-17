import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/test_catalogue.dart';
import '../../../../core/database/legacy_import.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/media/image_store.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';

/// The shop's configuration, and the three dangerous buttons.
class SettingsLocalDataSource {
  SettingsLocalDataSource(this._database);

  final AppDatabase _database;

  Map<String, String> all() => _database.settingsSnapshot;

  int get imageBytes => ImageStore.bytesUsed();

  /// Deletes every picture no row points at.
  ///
  /// A photo is copied into the store the moment it is chosen, so a manager
  /// who picks one and then closes the form without saving leaves a file
  /// behind. This is the broom for that, and for the pictures of items that
  /// have since been deleted.
  Future<int> cleanUpImages() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT image_path FROM items      WHERE IFNULL(image_path, '') <> ''
      UNION
      SELECT image_path FROM categories WHERE IFNULL(image_path, '') <> ''
    ''');
    return ImageStore.prune(<String>{
      for (final Map<String, Object?> r in rows) '${r['image_path']}',
    });
  }

  bool get testDataLoaded => TestCatalogue.isLoaded(_database);

  /// Fills the shop with a supermarket's catalogue so the till, the reports
  /// and the expiry screen have something to work on. Goes in through
  /// [TestCatalogue], which posts the opening stock properly, so a database
  /// with test data in it still balances.
  Future<TestCatalogueReport> seedTestCatalogue({int? userId}) =>
      TestCatalogue.run(_database, userId: userId);

  Future<void> save(Map<String, String> values) async {
    await _database.setSettings(values);

    // The keys, not the values: a settings change is worth knowing about, and
    // some of these values are a shop's private business.
    await Audit.write(
      _database.db,
      action: Audit.settingsSave,
      entity: 'settings',
      detail: values.keys.join(', '),
    );

    // The formatter is a process-wide singleton, so it has to be told when the
    // currency or the number of decimals changes — otherwise the till keeps
    // printing yesterday's format until the app is restarted.
    Fmt.configure(
      symbol: _database.settingString('currency_symbol', 'IQD'),
      decimals: _database.settingInt('currency_decimals'),
      locale: _database.settingString('language', 'en'),
    );
  }

  /// Copies the database file somewhere the user chose.
  ///
  /// WAL means recent writes may still be sitting in a side file, so the
  /// journal is checkpointed first — a backup that is missing the last hour of
  /// sales is worse than no backup, because nobody finds out until they need
  /// it.
  Future<String> backupTo(String directory) async {
    await _database.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

    final String source = await _database.defaultPath();
    final String stamp = Time.stamp().replaceAll(RegExp(r'[:T]'), '-');
    final String target = p.join(directory, 'cashier-backup-$stamp.db');

    await File(source).copy(target);
    return target;
  }

  /// Replaces the live database with a backup.
  ///
  /// The current file is kept beside the new one with a `.replaced` suffix
  /// rather than deleted: restoring the wrong backup is a mistake people make
  /// exactly once, and it should be recoverable.
  Future<void> restoreFrom(String backupPath) async {
    final File backup = File(backupPath);
    if (!backup.existsSync()) {
      throw const AppFailure.notFound('That backup file is not there.');
    }

    final String live = await _database.defaultPath();
    await _database.close();

    final File current = File(live);
    if (current.existsSync()) {
      final String stamp = Time.stamp().replaceAll(RegExp(r'[:T]'), '-');
      await current.rename('$live.replaced-$stamp');
    }
    // The side files belong to the database that is being replaced.
    for (final String suffix in <String>['-wal', '-shm']) {
      final File side = File('$live$suffix');
      if (side.existsSync()) await side.delete();
    }

    await backup.copy(live);
  }

  Future<LegacyImportReport> importLegacy(String path, {int? userId}) async {
    final LegacyImportReport report = await LegacyImporter(
      newDb: _database,
      legacyPath: path,
      userId: userId,
    ).run();

    // Everything the importer wrote went in behind the settings cache and the
    // account-id cache, so both are dropped.
    await _database.loadSettings();
    _database.forgetAccountCache();
    return report;
  }

  Future<String> defaultBackupDirectory() async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory backups = Directory(p.join(dir.path, 'backups'));
    if (!backups.existsSync()) await backups.create(recursive: true);
    return backups.path;
  }

  Future<String> databasePath() => _database.defaultPath();

  /// Rough size of the database on disk, for the settings screen.
  Future<int> databaseBytes() async {
    final File file = File(await _database.defaultPath());
    return file.existsSync() ? file.lengthSync() : 0;
  }
}
