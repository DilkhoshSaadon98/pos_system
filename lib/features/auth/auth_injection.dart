import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import 'data/datasources/auth_local_datasource.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'domain/repositories/auth_repository.dart';
import 'presentation/cubit/auth_cubit.dart';

void initAuthInjection() {
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl<AuthLocalDataSource>()),
  );

  sl.registerLazySingleton<AuthCubit>(() => AuthCubit(sl<AuthRepository>()));
}
