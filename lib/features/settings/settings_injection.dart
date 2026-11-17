import 'package:dartz/dartz.dart';

import '../../core/backup/backup_scheduler.dart';
import '../../core/database/app_database.dart';
import '../../core/database/test_catalogue.dart';
import '../../core/database/legacy_import.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import 'data/datasources/settings_local_datasource.dart';

abstract class SettingsRepository {
  Map<String, String> all();

  Future<Result<Unit>> save(Map<String, String> values);

  Future<Result<String>> backup({String? directory});

  Future<Result<Unit>> restore(String backupPath);

  Future<Result<LegacyImportReport>> importLegacy(String path, {int? userId});

  int get imageBytes;

  Future<Result<int>> cleanUpImages();

  bool get testDataLoaded;

  Future<Result<TestCatalogueReport>> seedTestCatalogue({int? userId});

  Future<Result<String>> databasePath();

  Future<Result<int>> databaseBytes();
}

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  @override
  Map<String, String> all() => _local.all();

  @override
  Future<Result<Unit>> save(Map<String, String> values) =>
      guardVoid(() => _local.save(values));

  @override
  Future<Result<String>> backup({String? directory}) => guard(() async {
        final String target =
            directory ?? await _local.defaultBackupDirectory();
        return _local.backupTo(target);
      });

  @override
  Future<Result<Unit>> restore(String backupPath) =>
      guardVoid(() => _local.restoreFrom(backupPath));

  @override
  Future<Result<LegacyImportReport>> importLegacy(String path, {int? userId}) =>
      guard(() => _local.importLegacy(path, userId: userId));

  @override
  int get imageBytes => _local.imageBytes;

  @override
  Future<Result<int>> cleanUpImages() => guard(_local.cleanUpImages);

  @override
  bool get testDataLoaded => _local.testDataLoaded;

  @override
  Future<Result<TestCatalogueReport>> seedTestCatalogue({int? userId}) =>
      guard(() => _local.seedTestCatalogue(userId: userId));

  @override
  Future<Result<String>> databasePath() => guard(_local.databasePath);

  @override
  Future<Result<int>> databaseBytes() => guard(_local.databaseBytes);
}

void initSettingsInjection() {
  sl.registerLazySingleton<SettingsLocalDataSource>(
    () => SettingsLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsLocalDataSource>()),
  );

  // The scheduler is given the one thing it needs — how to make a copy — so
  // that `core/` keeps knowing nothing about this feature.
  sl.registerLazySingleton<BackupScheduler>(
    () => BackupScheduler(
      sl<AppDatabase>(),
      copy: (String directory) async {
        final SettingsLocalDataSource local = sl<SettingsLocalDataSource>();
        final String target = directory.isEmpty
            ? await local.defaultBackupDirectory()
            : directory;
        return local.backupTo(target);
      },
    ),
  );
}
