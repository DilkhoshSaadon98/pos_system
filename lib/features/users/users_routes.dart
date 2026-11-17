import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'presentation/cubit/users_cubit.dart';
import 'presentation/pages/users_page.dart';
import 'users_injection.dart';

class UsersRoutes {
  const UsersRoutes._();

  static const String path = '/users';

  static Widget standalone() => BlocProvider<UsersCubit>(
        create: (_) => UsersCubit(sl<UsersRepository>())..load(),
        child: const UsersPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
