import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/catalog_local_datasource.dart';
import 'data/repositories/catalog_repository_impl.dart';
import 'domain/repositories/catalog_repository.dart';

void initCatalogInjection() {
  sl.registerLazySingleton<CatalogLocalDataSource>(
    () => CatalogLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<CatalogRepository>(
    () => CatalogRepositoryImpl(sl<CatalogLocalDataSource>()),
  );
}
