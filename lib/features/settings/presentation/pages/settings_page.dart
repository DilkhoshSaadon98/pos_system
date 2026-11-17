import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/backup/backup_scheduler.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/test_catalogue.dart';
import '../../../../core/database/legacy_import.dart';
import '../../../../core/display/customer_display.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/localization/language_cubit.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/settings_cubit.dart';

/// Everything about the shop that the rest of the app reads.
///
/// The three at the bottom are kept apart on purpose: a backup is harmless, a
/// restore replaces everything, and an import brings in data whose old ledger
/// was wrong. Each one says what it will do before it does it.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (SettingsState a, SettingsState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, SettingsState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<SettingsCubit>().clearFailure();
      },
      builder: (BuildContext context, SettingsState state) {
        final SettingsCubit cubit = context.read<SettingsCubit>();

        if (state.status.isBusyFirstTime) {
          return const Center(child: CircularProgressIndicator());
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: state.hasChanges
              ? FloatingActionButton.extended(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final bool ok = await cubit.save();
                          if (ok && context.mounted) {
                            AppSnack.success(
                                context, context.tr(AppText.saved));
                          }
                        },
                  icon: const Icon(Icons.check),
                  label: Text(context.tr(AppText.save)),
                )
              : null,
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              20,
              Responsive.isMobile(context) ? 14 : 24,
              100,
            ),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.settingsTitle),
                subtitle: state.databasePath,
                actions: <Widget>[
                  if (state.hasChanges)
                    OutlinedButton.icon(
                      onPressed: cubit.discard,
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(context.tr(AppText.reset)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Business(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Money(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _SecondCurrency(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Shifts(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Loyalty(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Display(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Backups(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Till(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _Appearance(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _DangerZone(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(dense: true, title: title, subtitle: subtitle),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Business extends StatefulWidget {
  const _Business({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Business> createState() => _BusinessState();
}

class _BusinessState extends State<_Business> {
  late final TextEditingController _name =
      TextEditingController(text: widget.state.read('business_name'));
  late final TextEditingController _phone =
      TextEditingController(text: widget.state.read('business_phone'));
  late final TextEditingController _address =
      TextEditingController(text: widget.state.read('business_address'));

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.tr(AppText.settingsBusiness),
      children: <Widget>[
        AppTextField(
          controller: _name,
          label: context.tr(AppText.settingsBusinessName),
          prefixIcon: Icons.storefront_outlined,
          onChanged: (String v) => widget.cubit.set('business_name', v),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: _phone,
                label: context.tr(AppText.phone),
                prefixIcon: Icons.call_outlined,
                onChanged: (String v) => widget.cubit.set('business_phone', v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AppTextField(
                controller: _address,
                label: context.tr(AppText.address),
                prefixIcon: Icons.place_outlined,
                onChanged: (String v) =>
                    widget.cubit.set('business_address', v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Money extends StatefulWidget {
  const _Money({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Money> createState() => _MoneyState();
}

class _MoneyState extends State<_Money> {
  late final TextEditingController _symbol =
      TextEditingController(text: widget.state.read('currency_symbol', 'IQD'));
  late final TextEditingController _rounding = TextEditingController(
    text: widget.state.readInt('rounding_step_minor') == 0
        ? ''
        : Fmt.moneyPlain(widget.state.readInt('rounding_step_minor')),
  );
  late final TextEditingController _tax = TextEditingController(
    text: widget.state.readInt('default_tax_rate_bp') == 0
        ? ''
        : '${widget.state.readInt('default_tax_rate_bp') / 100}',
  );

  @override
  void dispose() {
    _symbol.dispose();
    _rounding.dispose();
    _tax.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.tr(AppText.settingsCurrency),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: _symbol,
                label: context.tr(AppText.settingsCurrency),
                onChanged: (String v) =>
                    widget.cubit.set('currency_symbol', v.trim()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppDropdown<int>(
                label: context.tr(AppText.settingsDecimals),
                helper: context.tr(AppText.settingsDecimalsHint),
                value: widget.state.readInt('currency_decimals'),
                items: const <int>[0, 1, 2],
                itemLabel: (int n) => '$n',
                onChanged: (int? n) =>
                    widget.cubit.set('currency_decimals', '${n ?? 0}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MoneyField(
          controller: _rounding,
          label: context.tr(AppText.settingsRounding),
          helper: context.tr(AppText.settingsRoundingHint),
          onChanged: (Money? m) => widget.cubit
              .set('rounding_step_minor', '${(m ?? Money.zero).minor}'),
        ),
        const SizedBox(height: 14),
        PercentField(
          controller: _tax,
          label: context.tr(AppText.settingsTax),
          onChanged: (int? bp) =>
              widget.cubit.set('default_tax_rate_bp', '${bp ?? 0}'),
        ),
        AppSwitchTile(
          icon: Icons.receipt_long_outlined,
          title: context.tr(AppText.settingsTaxInclusive),
          value: widget.state.readBool('prices_include_tax'),
          onChanged: (bool v) =>
              widget.cubit.setBool('prices_include_tax', v),
        ),
      ],
    );
  }
}

class _Till extends StatefulWidget {
  const _Till({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Till> createState() => _TillState();
}

class _TillState extends State<_Till> {
  late final TextEditingController _prefixes = TextEditingController(
    text: widget.state.read('scale_prefixes', '20,21,22,23,24,25,26,27,28,29'),
  );

  @override
  void dispose() {
    _prefixes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.tr(AppText.navPos),
      children: <Widget>[
        AppDropdown<String>(
          label: context.tr(AppText.settingsPriceMode),
          value: widget.state.read('default_price_mode', 'retail'),
          items: PriceMode.values.map((PriceMode m) => m.dbValue).toList(),
          itemLabel: (String v) =>
              context.tr(PriceMode.fromDb(v).labelKey),
          onChanged: (String? v) =>
              widget.cubit.set('default_price_mode', v ?? 'retail'),
        ),
        AppSwitchTile(
          icon: Icons.trending_down,
          title: context.tr(AppText.settingsNegativeStock),
          value: widget.state.readBool('allow_negative_stock'),
          onChanged: (bool v) =>
              widget.cubit.setBool('allow_negative_stock', v),
        ),
        AppSwitchTile(
          icon: Icons.print_outlined,
          title: context.tr(AppText.settingsAutoPrint),
          value: widget.state.readBool('auto_print_receipt', true),
          onChanged: (bool v) => widget.cubit.setBool('auto_print_receipt', v),
        ),
        AppSwitchTile(
          icon: Icons.lock_outline,
          title: context.tr(AppText.settingsRequireLogin),
          value: widget.state.readBool('require_login', true),
          onChanged: (bool v) => widget.cubit.setBool('require_login', v),
        ),
        const SizedBox(height: 10),
        AppTextField(
          controller: _prefixes,
          label: context.tr(AppText.settingsScalePrefix),
          helper: context.tr(AppText.settingsScaleHint),
          prefixIcon: Icons.scale_outlined,
          onChanged: (String v) => widget.cubit.set('scale_prefixes', v),
        ),
        const SizedBox(height: 14),
        AppDropdown<String>(
          label: context.tr(AppText.itemsScaleCode),
          value: widget.state.read('scale_mode', 'weight'),
          items: const <String>['weight', 'price'],
          itemLabel: (String v) => context.tr(
            v == 'weight' ? AppText.posWeigh : AppText.price,
          ),
          onChanged: (String? v) =>
              widget.cubit.set('scale_mode', v ?? 'weight'),
        ),
      ],
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LanguageCubit, LanguageState>(
      builder: (BuildContext context, LanguageState language) {
        final LanguageCubit lang = context.read<LanguageCubit>();

        return _Card(
          title: context.tr(AppText.settingsTheme),
          children: <Widget>[
            AppDropdown<String>(
              label: context.tr(AppText.settingsLanguage),
              value: language.locale.languageCode,
              items: AppLocalizations.languageNames.keys.toList(),
              itemLabel: (String code) =>
                  AppLocalizations.languageNames[code] ?? code,
              onChanged: (String? code) {
                if (code != null) lang.setLocale(Locale(code));
              },
            ),
            const SizedBox(height: 14),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined, size: 18),
                  label: Text(context.tr(AppText.settingsThemeLight)),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined, size: 18),
                  label: Text(context.tr(AppText.settingsThemeDark)),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined, size: 18),
                  label: Text(context.tr(AppText.settingsThemeSystem)),
                ),
              ],
              selected: <ThemeMode>{language.themeMode},
              onSelectionChanged: (Set<ThemeMode> s) =>
                  lang.setThemeMode(s.first),
            ),
          ],
        );
      },
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _Card(
      title: context.tr(AppText.settingsDangerZone),
      subtitle: state.databaseBytes == 0
          ? null
          : '${(state.databaseBytes / 1024 / 1024).toStringAsFixed(1)} MB',
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.backup_outlined),
          title: Text(context.tr(AppText.settingsBackup)),
          subtitle: state.lastBackupPath == null
              ? null
              : Text(state.lastBackupPath!, style: theme.textTheme.bodySmall),
          trailing: FilledButton.tonal(
            onPressed: state.busy ? null : () => _backup(context),
            child: Text(context.tr(AppText.settingsBackup)),
          ),
        ),
        Divider(color: theme.surfaces.hairline),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(context.tr(AppText.settingsRestore)),
          subtitle: Text(
            context.tr(AppText.settingsRestoreWarning),
            style: theme.textTheme.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: state.busy ? null : () => _restore(context),
            child: Text(context.tr(AppText.settingsRestore)),
          ),
        ),
        Divider(color: theme.surfaces.hairline),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.upload_file_outlined),
          title: Text(context.tr(AppText.settingsImportOld)),
          subtitle: Text(
            context.tr(AppText.settingsImportWarning),
            style: theme.textTheme.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: state.busy ? null : () => _import(context),
            child: Text(context.tr(AppText.settingsImportOld)),
          ),
        ),
        Divider(color: theme.surfaces.hairline),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(context.tr(AppText.imageStorage)),
          subtitle: Text(
            '${(cubit.imageBytes / 1024 / 1024).toStringAsFixed(1)} MB',
            style: theme.textTheme.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: state.busy ? null : () => _cleanImages(context),
            child: Text(context.tr(AppText.imageCleanup)),
          ),
        ),
        Divider(color: theme.surfaces.hairline),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storefront_outlined),
          title: Text(context.tr(AppText.settingsTestData)),
          subtitle: Text(
            context.tr(cubit.testDataLoaded
                ? AppText.settingsTestLoaded
                : AppText.settingsTestHint),
            style: theme.textTheme.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: state.busy ? null : () => _testData(context),
            child: Text(context.tr(AppText.settingsTestLoad)),
          ),
        ),
        if (state.lastTest != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: theme.isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String line in state.lastTest!.summary)
                  Text('\u2022 $line', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
        if (state.lastImport != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: theme.isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String line in state.lastImport!.summary)
                  Text('• $line', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _backup(BuildContext context) async {
    final String? directory = await FilePicker.getDirectoryPath();
    final String? path = await cubit.backup(directory: directory);
    if (!context.mounted || path == null) return;
    AppSnack.success(
      context,
      context.tr(AppText.settingsBackupDone, params: <String, Object?>{
        'path': path,
      }),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final bool ok = await confirm(
      context,
      icon: Icons.settings_backup_restore,
      title: context.tr(AppText.settingsRestore),
      message: context.tr(AppText.settingsRestoreWarning),
      confirmLabel: context.tr(AppText.settingsRestore),
    );
    if (!ok || !context.mounted) return;

    // file_picker 12 hands back the file itself — an empty result is a
    // cancelled dialog, and `path` is null only when the file is not on disk.
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: context.mounted
          ? context.tr(AppText.settingsRestore)
          : null,
    );
    final String? path = picked?.path;
    if (path == null) return;

    final bool done = await cubit.restore(path);
    if (!context.mounted) return;
    if (done) {
      AppSnack.warning(context, context.tr(AppText.settingsRestartNeeded));
    }
  }

  Future<void> _cleanImages(BuildContext context) async {
    final int? removed = await cubit.cleanUpImages();
    if (!context.mounted || removed == null) return;
    AppSnack.success(
      context,
      context.tr(AppText.imageCleanupDone,
          params: <String, Object?>{'n': removed}),
    );
  }

  Future<void> _testData(BuildContext context) async {
    final bool ok = await confirm(
      context,
      icon: Icons.storefront_outlined,
      destructive: false,
      title: context.tr(AppText.settingsTestData),
      message: context.tr(AppText.settingsTestWarning),
      confirmLabel: context.tr(AppText.settingsTestLoad),
    );
    if (!ok || !context.mounted) return;

    final int? userId = context.read<AuthCubit>().state.user?.id;
    final TestCatalogueReport? report = await cubit.loadTestData(userId: userId);
    if (!context.mounted || report == null) return;

    AppSnack.success(
      context,
      context.tr(
        report.isEmpty ? AppText.settingsTestAlready : AppText.settingsTestDone,
        params: <String, Object?>{'n': report.items},
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final bool ok = await confirm(
      context,
      icon: Icons.upload_file_outlined,
      destructive: false,
      title: context.tr(AppText.settingsImportOld),
      message: context.tr(AppText.settingsImportWarning),
      confirmLabel: context.tr(AppText.settingsImportOld),
    );
    if (!ok || !context.mounted) return;

    final PlatformFile? picked = await FilePicker.pickFile();
    final String? path = picked?.path;
    if (path == null) return;

    final int? userId = context.mounted
        ? context.read<AuthCubit>().state.user?.id
        : null;
    final LegacyImportReport? report =
        await cubit.importLegacy(path, userId: userId);
    if (!context.mounted || report == null) return;

    AppSnack.success(context, context.tr(AppText.settingsImportDone));
  }
}

/// The second currency a shop actually takes over the counter.
class _SecondCurrency extends StatefulWidget {
  const _SecondCurrency({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_SecondCurrency> createState() => _SecondCurrencyState();
}

class _SecondCurrencyState extends State<_SecondCurrency> {
  late final TextEditingController _code =
      TextEditingController(text: widget.state.read('fx_currency_code', 'USD'));
  late final TextEditingController _symbol = TextEditingController(
      text: widget.state.read('fx_currency_symbol', '\$'));
  late final TextEditingController _rate =
      TextEditingController(text: widget.state.read('fx_rate', '1320'));
  late final TextEditingController _changeStep = TextEditingController(
    text: widget.state.readInt('fx_change_rounding') == 0
        ? ''
        : '${widget.state.readInt('fx_change_rounding')}',
  );

  @override
  void dispose() {
    _code.dispose();
    _symbol.dispose();
    _rate.dispose();
    _changeStep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.readBool('fx_enabled');

    return _Card(
      title: context.tr(AppText.settingsSecondCurrency),
      subtitle: context.tr(AppText.settingsSecondCurrencyHint),
      children: <Widget>[
        AppSwitchTile(
          icon: Icons.currency_exchange,
          title: context.tr(AppText.settingsSecondCurrencyOn),
          value: on,
          onChanged: (bool v) => setState(
              () => widget.cubit.setBool('fx_enabled', v)),
        ),
        if (on) ...<Widget>[
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: _code,
                  label: context.tr(AppText.settingsFxCode),
                  onChanged: (String v) => widget.cubit
                      .set('fx_currency_code', v.trim().toUpperCase()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _symbol,
                  label: context.tr(AppText.settingsFxSymbol),
                  onChanged: (String v) =>
                      widget.cubit.set('fx_currency_symbol', v.trim()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _rate,
            label: context.tr(AppText.settingsFxRate),
            helper: context.tr(AppText.settingsFxRateHint),
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (String v) => widget.cubit.set('fx_rate', v.trim()),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _changeStep,
            label: context.tr(AppText.settingsFxChangeRounding),
            helper: context.tr(AppText.settingsFxChangeRoundingHint),
            textAlign: TextAlign.end,
            keyboardType: TextInputType.number,
            onChanged: (String v) => widget.cubit
                .set('fx_change_rounding', v.trim().isEmpty ? '0' : v.trim()),
          ),
        ],
      ],
    );
  }
}

/// Whether the drawer has to be counted before the till will sell.
class _Shifts extends StatelessWidget {
  const _Shifts({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.tr(AppText.shiftsTitle),
      subtitle: context.tr(AppText.settingsShiftsHint),
      children: <Widget>[
        AppSwitchTile(
          icon: Icons.lock_clock,
          title: context.tr(AppText.settingsShiftsRequired),
          value: state.readBool('shifts_required', true),
          onChanged: (bool v) => cubit.setBool('shifts_required', v),
        ),
        AppSwitchTile(
          icon: Icons.print_outlined,
          title: context.tr(AppText.settingsShiftPrintOnClose),
          value: state.readBool('shift_print_on_close', true),
          onChanged: (bool v) => cubit.setBool('shift_print_on_close', v),
        ),
      ],
    );
  }
}

/// The screen the customer reads.
///
/// The address is spelled out rather than hidden behind a button because the
/// person setting this up is standing at a second monitor with a browser open
/// on it, and what they need from this card is something to type.
class _Display extends StatefulWidget {
  const _Display({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  late final TextEditingController _port = TextEditingController(
    text: widget.state.read('customer_display_port', '8088'),
  );

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    widget.cubit.setBool('customer_display', on);
    if (!on) {
      await CustomerDisplay.instance.stop();
      if (mounted) setState(() {});
      return;
    }
    final String? address = await CustomerDisplay.instance.start(
      port: int.tryParse(_port.text) ?? CustomerDisplay.defaultPort,
      lan: widget.state.readBool('customer_display_lan'),
    );
    if (!mounted) return;
    if (address == null) {
      AppSnack.warning(context, context.tr(AppText.settingsDisplayOffline));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = widget.state.readBool('customer_display');
    final String? address = CustomerDisplay.instance.url;

    return _Card(
      title: context.tr(AppText.settingsDisplay),
      subtitle: context.tr(AppText.settingsDisplayHint),
      children: <Widget>[
        AppSwitchTile(
          icon: Icons.tv_outlined,
          title: context.tr(AppText.settingsDisplay),
          value: on,
          onChanged: _toggle,
        ),
        AppSwitchTile(
          icon: Icons.wifi_tethering,
          title: context.tr(AppText.settingsDisplayLan),
          subtitle: context.tr(AppText.settingsDisplayLanHint),
          value: widget.state.readBool('customer_display_lan'),
          onChanged: (bool v) => widget.cubit.setBool('customer_display_lan', v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 200,
          child: AppTextField(
            controller: _port,
            label: context.tr(AppText.settingsDisplayPort),
            keyboardType: TextInputType.number,
            onChanged: (String v) =>
                widget.cubit.set('customer_display_port', v),
          ),
        ),
        if (on && address != null) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: theme.isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              address,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ],
    );
  }
}

/// The points scheme, and the price floor — two switches a shop sets once.
class _Loyalty extends StatefulWidget {
  const _Loyalty({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Loyalty> createState() => _LoyaltyState();
}

class _LoyaltyState extends State<_Loyalty> {
  late final TextEditingController _earn = TextEditingController(
    text: Fmt.moneyPlain(widget.state.readInt('loyalty_earn_per_minor', 100000)),
  );
  late final TextEditingController _value = TextEditingController(
    text: Fmt.moneyPlain(widget.state.readInt('loyalty_point_value_minor', 100)),
  );
  late final TextEditingController _min = TextEditingController(
    text: '${widget.state.readInt('loyalty_min_redeem_points', 0)}',
  );

  @override
  void dispose() {
    _earn.dispose();
    _value.dispose();
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.readBool('loyalty_enabled');

    return _Card(
      title: context.tr(AppText.settingsLoyalty),
      children: <Widget>[
        AppSwitchTile(
          icon: Icons.card_giftcard,
          title: context.tr(AppText.settingsLoyaltyOn),
          value: on,
          onChanged: (bool v) =>
              setState(() => widget.cubit.setBool('loyalty_enabled', v)),
        ),
        if (on) ...<Widget>[
          const SizedBox(height: 14),
          MoneyField(
            controller: _earn,
            label: context.tr(AppText.settingsLoyaltyEarn),
            onChanged: (Money? m) => widget.cubit.set(
              'loyalty_earn_per_minor',
              '${(m ?? Money.zero).minor}',
            ),
          ),
          const SizedBox(height: 14),
          MoneyField(
            controller: _value,
            label: context.tr(AppText.settingsLoyaltyValue),
            onChanged: (Money? m) => widget.cubit.set(
              'loyalty_point_value_minor',
              '${(m ?? Money.zero).minor}',
            ),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _min,
            label: context.tr(AppText.settingsLoyaltyMin),
            textAlign: TextAlign.end,
            keyboardType: TextInputType.number,
            onChanged: (String v) => widget.cubit.set(
              'loyalty_min_redeem_points',
              v.trim().isEmpty ? '0' : v.trim(),
            ),
          ),
        ],
        const SizedBox(height: 6),
        AppSwitchTile(
          icon: Icons.price_check,
          title: context.tr(AppText.settingsMinPrice),
          value: widget.state.readBool('enforce_min_price', true),
          onChanged: (bool v) => widget.cubit.setBool('enforce_min_price', v),
        ),
      ],
    );
  }
}

/// Where the automatic copies go, and how many are kept.
class _Backups extends StatefulWidget {
  const _Backups({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  State<_Backups> createState() => _BackupsState();
}

class _BackupsState extends State<_Backups> {
  late final TextEditingController _every = TextEditingController(
    text: '${widget.state.readInt('backup_every_hours', 24)}',
  );
  late final TextEditingController _keep = TextEditingController(
    text: '${widget.state.readInt('backup_keep', 14)}',
  );
  bool _running = false;

  @override
  void dispose() {
    _every.dispose();
    _keep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = widget.state.readBool('backup_auto');
    final String folder = widget.state.read('backup_folder');
    final String last = widget.state.read('backup_last_at');

    return _Card(
      title: context.tr(AppText.settingsBackupAuto),
      subtitle: last.isEmpty
          ? null
          : '${context.tr(AppText.settingsBackupLast)}: ${Fmt.dateTime(last)}',
      children: <Widget>[
        AppSwitchTile(
          icon: Icons.backup_outlined,
          title: context.tr(AppText.settingsBackupAutoOn),
          value: on,
          onChanged: (bool v) {
            setState(() => widget.cubit.setBool('backup_auto', v));
            // Saved first, then the clock restarted, so the timer reflects the
            // choice rather than the state it was in before it.
            widget.cubit.save().then((_) => sl<BackupScheduler>().start());
          },
        ),
        if (on) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  folder.isEmpty
                      ? context.tr(AppText.settingsBackupFolder)
                      : folder,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.surfaces.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _chooseFolder,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(context.tr(AppText.settingsBackupFolder)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: _every,
                  label: context.tr(AppText.settingsBackupEvery),
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.number,
                  onChanged: (String v) => widget.cubit
                      .set('backup_every_hours', v.trim().isEmpty ? '24' : v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _keep,
                  label: context.tr(AppText.settingsBackupKeep),
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.number,
                  onChanged: (String v) => widget.cubit
                      .set('backup_keep', v.trim().isEmpty ? '14' : v.trim()),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.tonalIcon(
            onPressed: _running ? null : _backupNow,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt, size: 18),
            label: Text(context.tr(AppText.settingsBackupNow)),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseFolder() async {
    final String? directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) return;
    widget.cubit.set('backup_folder', directory);
    await widget.cubit.save();
    sl<BackupScheduler>().start();
  }

  Future<void> _backupNow() async {
    setState(() => _running = true);
    // Saved first: a folder typed a moment ago must be the folder used.
    await widget.cubit.save();
    final BackupOutcome outcome =
        await sl<BackupScheduler>().runIfDue(force: true);
    if (!mounted) return;
    setState(() => _running = false);

    if (outcome.error != null) {
      AppSnack.error(context, outcome.error!);
    } else if (outcome.didCopy) {
      AppSnack.success(context, outcome.path!);
    }
  }
}
