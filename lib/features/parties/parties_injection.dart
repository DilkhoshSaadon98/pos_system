import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/parties_local_datasource.dart';
import 'data/repositories/parties_repository_impl.dart';
import 'domain/repositories/parties_repository.dart';

void initPartiesInjection() {
  sl.registerLazySingleton<PartiesLocalDataSource>(
    () => PartiesLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<PartiesRepository>(
    () => PartiesRepositoryImpl(sl<PartiesLocalDataSource>()),
  );
}
