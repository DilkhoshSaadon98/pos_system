import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/dashboard_local_datasource.dart';
import 'data/repositories/dashboard_repository_impl.dart';
import 'domain/repositories/dashboard_repository.dart';

void initDashboardInjection() {
  sl.registerLazySingleton<DashboardLocalDataSource>(
    () => DashboardLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(sl<DashboardLocalDataSource>()),
  );
}
