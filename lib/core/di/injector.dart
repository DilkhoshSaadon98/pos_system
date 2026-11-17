import 'package:get_it/get_it.dart';

import '../../features/accounting/accounting_injection.dart';
import '../../features/audit/audit_injection.dart';
import '../../features/auth/auth_injection.dart';
import '../../features/catalog/catalog_injection.dart';
import '../../features/dashboard/dashboard_injection.dart';
import '../../features/insights/insights_feature.dart';
import '../../features/inventory/inventory_injection.dart';
import '../../features/orders/orders_feature.dart';
import '../../features/parties/parties_injection.dart';
import '../../features/pos/pos_injection.dart';
import '../../features/printing/printing_injection.dart';
import '../../features/promotions/promotions_feature.dart';
import '../../features/purchases/purchases_injection.dart';
import '../../features/sales/sales_injection.dart';
import '../../features/settings/settings_injection.dart';
import '../../features/stocktake/stocktake_feature.dart';
import '../../features/shifts/shifts_injection.dart';
import '../../features/users/users_injection.dart';
import '../database/app_database.dart';
import '../localization/language_cubit.dart';

//? A service locator for the app's dependencies.
final GetIt sl = GetIt.instance;

Future<void> setupInjector(AppDatabase database) async {
  sl.registerSingleton<AppDatabase>(database);
  sl.registerLazySingleton<LanguageCubit>(() => LanguageCubit(sl<AppDatabase>()));

  initAuthInjection();
  initCatalogInjection();
  initInventoryInjection();
  initPartiesInjection();
  initSalesInjection();
  initPurchasesInjection();
  initPrintingInjection();
  initPosInjection();
  initDashboardInjection();
  initAccountingInjection();
  initUsersInjection();
  initSettingsInjection();
  initShiftsInjection();
  initAuditInjection();
  initOrdersInjection();
  initStocktakeInjection();
  initPromotionsInjection();
  initInsightsInjection();
}

Future<void> resetInjector() async {
  await sl.reset();
}
