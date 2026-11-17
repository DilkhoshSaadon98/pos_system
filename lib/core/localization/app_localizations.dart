import 'package:flutter/material.dart';

import 'translations.dart';

//? Localizations for the app, handling translations across different languages.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

//? Supported locales for the app, including English, Arabic, and Kurdish.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
    Locale('ckb'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'));

  static bool isRtl(Locale locale) =>
      locale.languageCode == 'ar' || locale.languageCode == 'ckb';

  static const Map<String, String> languageNames = <String, String>{
    'en': 'English',
    'ar': 'العربية',
    'ckb': 'کوردی',
  };

  Map<String, String> get _table =>
      AppTranslations.values[locale.languageCode] ??
      AppTranslations.values['en']!;

  //? Translates a given key into the appropriate language string, replacing any parameters if provided.
  String t(String key, {Map<String, Object?>? params}) {
    String value = _table[key] ?? AppTranslations.values['en']![key] ?? key;
    if (params != null) {
      params.forEach((String name, Object? v) {
        value = value.replaceAll('{$name}', '$v');
      });
    }
    return value;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppTranslations.values.containsKey(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension LocalizationX on BuildContext {
  /// `context.tr(AppText.save)`
  String tr(String key, {Map<String, Object?>? params}) =>
      AppLocalizations.of(this).t(key, params: params);

  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
