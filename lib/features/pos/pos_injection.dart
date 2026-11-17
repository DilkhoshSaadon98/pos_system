import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../catalog/data/datasources/catalog_local_datasource.dart';
import 'data/datasources/pos_local_datasource.dart';
import 'data/repositories/pos_repository_impl.dart';
import 'domain/repositories/pos_repository.dart';

void initPosInjection() {
  sl.registerLazySingleton<PosLocalDataSource>(
    () => PosLocalDataSource(
      sl<AppDatabase>(),
      sl<CatalogLocalDataSource>(),
    ),
  );

  sl.registerLazySingleton<PosRepository>(
    () => PosRepositoryImpl(sl<PosLocalDataSource>()),
  );
}
