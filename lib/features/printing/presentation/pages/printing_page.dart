import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/printer_profile.dart';
import '../cubit/printing_cubit.dart';

/// The printer screen, rebuilt around a live preview.
///
/// Left: the printers the shop has and the settings of the one selected.
/// Right: the page those settings produce, rendered by the same code that will
/// hand it to the printer. The old version had a settings form and a separate
/// "preview" button that opened the system dialog — which meant every change
/// was a guess until somebody wasted a roll of paper finding out.
class PrintingPage extends StatelessWidget {
  const PrintingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PrintingCubit, PrintingState>(
      listenWhen: (PrintingState a, PrintingState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, PrintingState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PrintingCubit>().clearFailure();
      },
      builder: (BuildContext context, PrintingState state) {
        if (state.status.isBusyFirstTime) {
          return const Center(child: CircularProgressIndicator());
        }

        final Widget settings = _Settings(state: state);
        final Widget preview = _Preview(state: state);

        if (Responsive.isCompact(context)) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              settings,
              const SizedBox(height: 16),
              SizedBox(height: 520, child: preview),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 460,
                child: SingleChildScrollView(child: settings),
              ),
              const SizedBox(width: 20),
              Expanded(child: preview),
            ],
          ),
        );
      },
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.state});

  final PrintingState state;

  @override
  Widget build(BuildContext context) {
    final PrintingCubit cubit = context.read<PrintingCubit>();
    final PrinterProfile? draft = state.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: context.tr(AppText.printProfiles),
          actions: <Widget>[
            FilledButton.icon(
              onPressed: cubit.startNew,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.printNewProfile)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (state.profiles.isEmpty && draft?.id == null)
          Card(
            child: EmptyState(
              icon: Icons.print_disabled_outlined,
              message: context.tr(AppText.printNoPrinter),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final PrinterProfile p in state.profiles)
                ChoiceChip(
                  avatar: p.isDefault
                      ? const Icon(Icons.star, size: 15, color: AppColors.warning)
                      : null,
                  label: Text(p.name),
                  selected: p.id == draft?.id,
                  onSelected: (_) => cubit.select(p),
                ),
            ],
          ),
        const SizedBox(height: 18),
        if (draft != null) _ProfileForm(draft: draft, state: state),
      ],
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.draft, required this.state});

  final PrinterProfile draft;
  final PrintingState state;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _header;
  late final TextEditingController _footer;
  int? _boundTo;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.name);
    _address = TextEditingController(text: widget.draft.address ?? '');
    _header = TextEditingController(text: widget.draft.headerText);
    _footer = TextEditingController(text: widget.draft.footerText);
    _boundTo = widget.draft.id;
  }

  @override
  void didUpdateWidget(covariant _ProfileForm old) {
    super.didUpdateWidget(old);
    // Switching to a different printer refills the boxes; editing the one on
    // screen must not, or every keystroke would fight the cursor.
    if (widget.draft.id != _boundTo) {
      _boundTo = widget.draft.id;
      _name.text = widget.draft.name;
      _address.text = widget.draft.address ?? '';
      _header.text = widget.draft.headerText;
      _footer.text = widget.draft.footerText;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PrintingCubit cubit = context.read<PrintingCubit>();
    final PrinterProfile d = widget.draft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              controller: _name,
              label: context.tr(AppText.name),
              prefixIcon: Icons.print_outlined,
              onChanged: (String v) => cubit.edit(d.copyWith(name: v)),
            ),
            const SizedBox(height: 14),
            AppDropdown<PrinterDriver>(
              label: context.tr(AppText.printDriver),
              value: d.driver,
              items: PrinterDriver.values,
              itemLabel: (PrinterDriver x) => context.tr(x.labelKey),
              onChanged: (PrinterDriver? x) =>
                  x == null ? null : cubit.edit(d.copyWith(driver: x)),
            ),
            if (d.driver.needsAddress) ...<Widget>[
              const SizedBox(height: 14),
              AppTextField(
                controller: _address,
                label: context.tr(AppText.printAddress),
                prefixIcon: Icons.lan_outlined,
                onChanged: (String v) => cubit.edit(d.copyWith(address: v)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDropdown<PaperSize>(
                    label: context.tr(AppText.printPaper),
                    value: d.paper,
                    items: PaperSize.values,
                    itemLabel: (PaperSize x) => context.tr(x.labelKey),
                    onChanged: (PaperSize? x) =>
                        x == null ? null : cubit.edit(d.copyWith(paper: x)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<int>(
                    label: context.tr(AppText.printCopies),
                    value: d.copies,
                    items: const <int>[1, 2, 3, 4, 5],
                    itemLabel: (int x) => '$x',
                    onChanged: (int? x) =>
                        x == null ? null : cubit.edit(d.copyWith(copies: x)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _header,
              label: context.tr(AppText.printHeader),
              maxLines: 2,
              onChanged: (String v) => cubit.edit(d.copyWith(headerText: v)),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _footer,
              label: context.tr(AppText.printFooter),
              maxLines: 2,
              onChanged: (String v) => cubit.edit(d.copyWith(footerText: v)),
            ),
            const SizedBox(height: 6),
            AppSwitchTile(
              icon: Icons.qr_code_2,
              title: context.tr(AppText.printShowBarcode),
              value: d.showBarcode,
              onChanged: (bool v) => cubit.edit(d.copyWith(showBarcode: v)),
            ),
            AppSwitchTile(
              icon: Icons.image_outlined,
              title: context.tr(AppText.printShowLogo),
              value: d.showLogo,
              onChanged: (bool v) => cubit.edit(d.copyWith(showLogo: v)),
            ),
            AppSwitchTile(
              icon: Icons.receipt_outlined,
              title: context.tr(AppText.printShowTaxLines),
              value: d.showTaxLines,
              onChanged: (bool v) => cubit.edit(d.copyWith(showTaxLines: v)),
            ),
            AppSwitchTile(
              icon: Icons.bolt_outlined,
              title: context.tr(AppText.printAuto),
              value: d.autoPrint,
              onChanged: (bool v) => cubit.edit(d.copyWith(autoPrint: v)),
            ),
            AppSwitchTile(
              icon: Icons.savings_outlined,
              title: context.tr(AppText.printOpenDrawer),
              value: d.openDrawer,
              onChanged: (bool v) => cubit.edit(d.copyWith(openDrawer: v)),
            ),
            AppSwitchTile(
              icon: Icons.star_outline,
              title: context.tr(AppText.printDefault),
              value: d.isDefault,
              onChanged: (bool v) => cubit.edit(d.copyWith(isDefault: v)),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                if (d.id != null)
                  TextButton.icon(
                    onPressed: () async {
                      if (!await confirmDelete(context, what: d.name)) return;
                      await cubit.delete(d.id!);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(context.tr(AppText.delete)),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.danger),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: widget.state.busy
                      ? null
                      : () async {
                          final bool ok = await cubit.save();
                          if (ok && context.mounted) {
                            AppSnack.success(
                                context, context.tr(AppText.saved));
                          }
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(context.tr(AppText.save)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.state});

  final PrintingState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PrintingCubit cubit = context.read<PrintingCubit>();

    return Card(
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            decoration: BoxDecoration(
              color: theme.surfaces.raised,
              border:
                  Border(bottom: BorderSide(color: theme.surfaces.hairline)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.visibility_outlined,
                    size: 18, color: theme.surfaces.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(AppText.printLivePreview),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (state.rendering)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: state.preview == null || state.busy
                      ? null
                      : () async {
                          final bool ok = await cubit.testPrint();
                          if (ok && context.mounted) {
                            AppSnack.info(
                                context, context.tr(AppText.printSent));
                          }
                        },
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(context.tr(AppText.printTest)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final bool ok = await cubit.openDrawer();
                          if (context.mounted && ok) {
                            AppSnack.info(
                                context, context.tr(AppText.printDrawerOpened));
                          }
                        },
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: Text(context.tr(AppText.printOpenDrawer)),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.preview == null
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: context.tr(AppText.printPreview),
                  )
                : ColoredBox(
                    color: theme.surfaces.page,
                    child: PdfPreview(
                      build: (_) async => state.preview!,
                      useActions: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      scrollViewDecoration:
                          BoxDecoration(color: theme.surfaces.page),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
