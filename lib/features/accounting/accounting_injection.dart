import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/accounting_local_datasource.dart';
import 'data/repositories/accounting_repository_impl.dart';
import 'domain/repositories/accounting_repository.dart';

void initAccountingInjection() {
  sl.registerLazySingleton<AccountingLocalDataSource>(
    () => AccountingLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<AccountingRepository>(
    () => AccountingRepositoryImpl(sl<AccountingLocalDataSource>()),
  );
}
