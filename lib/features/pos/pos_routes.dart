import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../catalog/domain/repositories/catalog_repository.dart';
import '../parties/domain/repositories/parties_repository.dart';
import '../printing/domain/repositories/printing_repository.dart';
import '../auth/presentation/cubit/auth_cubit.dart';
import '../sales/domain/repositories/sales_repository.dart';
import '../promotions/promotions_feature.dart';
import '../shifts/shifts_injection.dart';
import 'domain/repositories/pos_repository.dart';
import 'presentation/cubit/pos_cubit.dart';
import 'presentation/pages/pos_page.dart';


class PosRoutes {
  const PosRoutes._();

  static const String path = '/pos';

  static Widget standalone() => Builder(
        builder: (BuildContext context) => BlocProvider<PosCubit>(
          create: (_) => PosCubit(
            catalog: sl<CatalogRepository>(),
            sales: sl<SalesRepository>(),
            parties: sl<PartiesRepository>(),
            pos: sl<PosRepository>(),
            printing: sl<PrintingRepository>(),
            shifts: sl<ShiftsRepository>(),
            promotions: sl<PromotionsRepository>(),
            userId: context.read<AuthCubit>().state.user?.id,
            role: context.read<AuthCubit>().state.user?.role,
          )..load(),
          child: const PosPage(),
        ),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
