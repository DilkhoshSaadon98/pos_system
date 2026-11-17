import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../database/app_database.dart';
import '../format/formatters.dart';


class LanguageState {
  const LanguageState({
    this.locale = const Locale('en'),
    this.themeMode = ThemeMode.system,
    this.tillIsDark = true,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final bool tillIsDark;

  LanguageState copyWith({
    Locale? locale,
    ThemeMode? themeMode,
    bool? tillIsDark,
  }) =>
      LanguageState(
        locale: locale ?? this.locale,
        themeMode: themeMode ?? this.themeMode,
        tillIsDark: tillIsDark ?? this.tillIsDark,
      );
}

class LanguageCubit extends Cubit<LanguageState> {
  LanguageCubit(this._database) : super(const LanguageState());

  final AppDatabase _database;

  void loadFromSettings() {
    final String code = _database.settingString('language', 'en');
    final String mode = _database.settingString('theme_mode', 'system');
    emit(LanguageState(
      locale: Locale(code),
      themeMode: _modeFrom(mode),
      tillIsDark: _database.settingString('pos_theme', 'dark') == 'dark',
    ));
  }

  Future<void> setLocale(Locale locale) async {
    emit(state.copyWith(locale: locale));
    await _database.setSetting('language', locale.languageCode);
    Fmt.instance.localeName = locale.languageCode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(state.copyWith(themeMode: mode));
    await _database.setSetting('theme_mode', mode.name);
  }

  Future<void> setTillDark(bool dark) async {
    emit(state.copyWith(tillIsDark: dark));
    await _database.setSetting('pos_theme', dark ? 'dark' : 'light');
  }

  static ThemeMode _modeFrom(String name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
