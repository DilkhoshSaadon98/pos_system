import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/purchases_local_datasource.dart';
import 'data/repositories/purchases_repository_impl.dart';
import 'domain/repositories/purchases_repository.dart';

void initPurchasesInjection() {
  sl.registerLazySingleton<PurchasesLocalDataSource>(
    () => PurchasesLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<PurchasesRepository>(
    () => PurchasesRepositoryImpl(sl<PurchasesLocalDataSource>()),
  );
}
