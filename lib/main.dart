import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/backup/backup_scheduler.dart';
import 'core/database/app_database.dart';
import 'core/database/test_catalogue.dart';
import 'core/display/customer_display.dart';
import 'core/di/injector.dart';
import 'core/format/formatters.dart';
import 'core/media/image_store.dart';
import 'core/security/permissions.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  //? Initialize local image directory storage
  await ImageStore.configure();

  // ** Setup database connection and load global store configurations
  final database = AppDatabase.instance;
  await database.open();
  await database.loadSettings();

  // ? Seeds dummy store catalogue strictly in Debug mode for local testing
  // ! Never runs on Release builds to prevent corrupting real store inventories
  if (kDebugMode && !TestCatalogue.isLoaded(database)) {
    final seeded = await TestCatalogue.run(database);
    debugPrint('test catalogue: ${seeded.summary.join(' | ')}');
    await database.loadSettings();
  }

  //? Configure global currency and locale formatting options
  Fmt.configure(
    symbol: database.settingString('currency_symbol', 'IQD'),
    decimals: database.settingInt('currency_decimals'),
    locale: database.settingString('language', 'en'),
  );

  //? Register service locator dependencies & singletons
  await setupInjector(database);

  //? Load user security roles and start background auto-backup timer
  await Permissions.load(database);
  sl<BackupScheduler>().start();

  //? Initialize customer-facing secondary display if feature flag is enabled
  if (database.settingBool('customer_display')) {
    await CustomerDisplay.instance.start(
      port: database.settingInt(
        'customer_display_port',
        CustomerDisplay.defaultPort,
      ),
      lan: database.settingBool('customer_display_lan'),
    );
  }

  // TODO: Uncomment desktop window configuration for production multi-platform release
  /*
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        minimumSize: Size(1024, 640),
        size: Size(1440, 900),
        center: true,
        title: 'Cashier System',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  */

  runApp(const CashierApp());
}