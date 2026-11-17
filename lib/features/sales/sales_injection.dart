import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/sales_local_datasource.dart';
import 'data/repositories/sales_repository_impl.dart';
import 'domain/repositories/sales_repository.dart';

void initSalesInjection() {
  sl.registerLazySingleton<SalesLocalDataSource>(
    () => SalesLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<SalesRepository>(
    () => SalesRepositoryImpl(sl<SalesLocalDataSource>()),
  );
}
