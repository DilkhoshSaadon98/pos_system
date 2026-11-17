import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/printing_repository.dart';
import 'presentation/cubit/printing_cubit.dart';
import 'presentation/pages/printing_page.dart';

class PrintingRoutes {
  const PrintingRoutes._();

  static const String path = '/printing';

  static Widget standalone() => BlocProvider<PrintingCubit>(
        create: (_) => PrintingCubit(sl<PrintingRepository>())..load(),
        child: const PrintingPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
