import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../auth/presentation/cubit/auth_cubit.dart';
import 'presentation/cubit/shift_cubit.dart';
import 'presentation/pages/shifts_page.dart';
import 'shifts_injection.dart';

class ShiftsRoutes {
  const ShiftsRoutes._();

  static const String path = '/shifts';

  /// The drawer belongs to whoever is signed in.
  ///
  /// The [Builder] is not decoration: navigation entries are built without a
  /// context, and the cubit needs one to find the signed-in cashier. This puts
  /// the lookup inside the tree, where `AuthCubit` is actually reachable.
  static Widget standalone() => Builder(
        builder: (BuildContext context) => BlocProvider<ShiftCubit>(
          create: (_) => ShiftCubit(
            sl<ShiftsRepository>(),
            userId: context.read<AuthCubit>().state.user?.id,
          )..load(),
          child: const ShiftsPage(),
        ),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
