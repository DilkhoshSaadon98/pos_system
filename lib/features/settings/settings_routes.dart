import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'presentation/cubit/settings_cubit.dart';
import 'presentation/pages/settings_page.dart';
import 'settings_injection.dart';

class SettingsRoutes {
  const SettingsRoutes._();

  static const String path = '/settings';

  static Widget standalone() => BlocProvider<SettingsCubit>(
        create: (_) => SettingsCubit(sl<SettingsRepository>())..load(),
        child: const SettingsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
