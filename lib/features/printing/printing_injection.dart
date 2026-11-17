import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/language_cubit.dart';
import 'data/datasources/printing_local_datasource.dart';
import 'data/repositories/printing_repository_impl.dart';
import 'domain/repositories/printing_repository.dart';

void initPrintingInjection() {
  sl.registerLazySingleton<PrintingLocalDataSource>(
    () => PrintingLocalDataSource(sl<AppDatabase>()),
  );

  sl.registerLazySingleton<PrintingRepository>(
    () => PrintingRepositoryImpl(
      sl<PrintingLocalDataSource>(),
      // A receipt in Arabic or Kurdish has to be laid out right to left. The
      // repository is told how to find that out rather than reading a global,
      // so a test can render both directions without a widget tree.
      () => AppLocalizations.isRtl(sl<LanguageCubit>().state.locale),
    ),
  );
}
