import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/dashboard_repository.dart';
import 'presentation/cubit/dashboard_cubit.dart';
import 'presentation/pages/dashboard_page.dart';

class DashboardRoutes {
  const DashboardRoutes._();

  static const String path = '/';

  static Widget standalone() => BlocProvider<DashboardCubit>(
        create: (_) => DashboardCubit(sl<DashboardRepository>())..load(),
        child: const DashboardPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
