import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/sales_repository.dart';
import 'presentation/cubit/sale_return_cubit.dart';
import 'presentation/cubit/sales_cubit.dart';
import 'presentation/pages/sale_return_page.dart';
import 'presentation/pages/sales_page.dart';

class SalesRoutes {
  const SalesRoutes._();

  static const String list = '/sales';
  static const String returns = '/sales/returns';

  static Widget standalone() => BlocProvider<SalesCubit>(
        create: (_) => SalesCubit(sl<SalesRepository>())..load(),
        child: const SalesPage(),
      );

  static Widget returnsPage() => BlocProvider<SaleReturnCubit>(
        create: (_) => SaleReturnCubit(sl<SalesRepository>()),
        child: const SaleReturnPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        list: (_) => standalone(),
        returns: (_) => returnsPage(),
      };
}
