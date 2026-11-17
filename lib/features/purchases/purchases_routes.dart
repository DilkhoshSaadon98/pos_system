import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/purchases_repository.dart';
import 'presentation/cubit/purchase_return_cubit.dart';
import 'presentation/cubit/purchases_cubit.dart';
import 'presentation/pages/purchase_return_page.dart';
import 'presentation/pages/purchases_page.dart';

class PurchasesRoutes {
  const PurchasesRoutes._();

  static const String list = '/purchases';
  static const String returns = '/purchases/returns';

  static Widget standalone() => BlocProvider<PurchasesCubit>(
        create: (_) => PurchasesCubit(sl<PurchasesRepository>())..load(),
        child: const PurchasesPage(),
      );

  static Widget returnsPage() => BlocProvider<PurchaseReturnCubit>(
        create: (_) => PurchaseReturnCubit(sl<PurchasesRepository>()),
        child: const PurchaseReturnPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        list: (_) => standalone(),
        returns: (_) => returnsPage(),
      };
}
