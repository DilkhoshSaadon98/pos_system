import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/di/injector.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/app_text.dart';
import 'core/localization/language_cubit.dart';
import 'core/state/app_status.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_snack.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/shell/presentation/cubit/shell_cubit.dart';
import 'features/shell/presentation/pages/shell_page.dart';


class CashierApp extends StatelessWidget {
  const CashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<LanguageCubit>(
          create: (_) => sl<LanguageCubit>()..loadFromSettings(),
        ),
        BlocProvider<AuthCubit>(
          create: (_) => sl<AuthCubit>()..bootstrap(),
        ),
        BlocProvider<ShellCubit>(create: (_) => ShellCubit()),
      ],
      child: BlocBuilder<LanguageCubit, LanguageState>(
        builder: (BuildContext context, LanguageState language) {
          return MaterialApp(
            title: 'Cashier System',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: AppSnack.messengerKey,
            locale: language.locale,
            themeMode: language.themeMode,
            theme: AppTheme.light(fontFamily: 'NotoKufiArabic'),
            darkTheme: AppTheme.dark(fontFamily: 'NotoKufiArabic'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback:
                (Locale? locale, Iterable<Locale> supported) {
              if (locale?.languageCode == 'ckb') return const Locale('ckb');
              return locale;
            },
            localeListResolutionCallback:
                (List<Locale>? locales, Iterable<Locale> supported) =>
                    language.locale,
            builder: (BuildContext context, Widget? child) {
              return Directionality(
                textDirection: AppLocalizations.isRtl(language.locale)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _Gate(),
          );
        },
      ),
    );
  }
}

/// Sign-in screen or shell, depending on who is here.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (BuildContext context, AuthState state) {
        if (state.status.isBusyFirstTime) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.tr(AppText.loading)),
                ],
              ),
            ),
          );
        }
        //TODO : return state.isSignedIn ? const ShellPage() : const LoginPage();
        return const ShellPage();
      },
    );
  }
}
