import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/catalog_repository.dart';
import 'presentation/cubit/items_cubit.dart';
import 'presentation/pages/items_page.dart';

/// How the catalogue is reached.
///
/// The cubit is created here rather than in the injector, so it lives exactly
/// as long as the screen does: leaving the items page disposes it, and coming
/// back builds a fresh one that loads current data. Registering it in the
/// service locator would keep yesterday's list alive behind the scenes — which
/// is what `Get.lazyPut(fenix: true)` used to do.
class CatalogRoutes {
  const CatalogRoutes._();

  static const String items = '/items';

  static Widget page() => const ItemsPage();

  static Widget standalone() => BlocProvider<ItemsCubit>(
        create: (_) => ItemsCubit(sl<CatalogRepository>())..load(),
        child: const ItemsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        items: (_) => standalone(),
      };
}
