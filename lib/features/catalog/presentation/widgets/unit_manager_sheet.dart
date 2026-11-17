import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../cubit/items_cubit.dart';

/// The shop's unit library — piece, box, carton, kilogram.
///
/// "Allow fractions" is the only setting here that changes behaviour: it is
/// what tells the till whether the quantity keypad offers a decimal point. You
/// can sell half a kilo; you cannot sell half a piece, and a till that lets you
/// try produces stock figures nobody can reconcile.
Future<void> showUnitManager(BuildContext context, ItemsCubit cubit) =>
    showAppModal<void>(
      context,
      width: 520,
      title: context.tr(AppText.itemsUnitsLibrary),
      builder: (BuildContext context) => _UnitManager(cubit: cubit),
    );

class _UnitManager extends StatefulWidget {
  const _UnitManager({required this.cubit});

  final ItemsCubit cubit;

  @override
  State<_UnitManager> createState() => _UnitManagerState();
}

class _UnitManagerState extends State<_UnitManager> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  bool _fraction = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final bool ok = await widget.cubit.saveUnit(UnitSaveRequest(
      name: name,
      symbol: _symbol.text,
      allowFraction: _fraction,
    ));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _name.clear();
        _symbol.clear();
        _fraction = false;
      }
    });
    if (!ok) {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<UnitDef> units = widget.cubit.state.units;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _name,
                label: context.tr(AppText.name),
                autofocus: true,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: AppTextField(
                controller: _symbol,
                label: context.tr(AppText.itemsSymbol),
              ),
            ),
          ],
        ),
        AppSwitchTile(
          icon: Icons.pie_chart_outline,
          title: context.tr(AppText.itemsAllowFraction),
          value: _fraction,
          onChanged: (bool v) => setState(() => _fraction = v),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr(AppText.add)),
          ),
        ),
        const SizedBox(height: 18),
        if (units.isEmpty)
          EmptyState(
            icon: Icons.straighten_outlined,
            message: context.tr(AppText.nothingYet),
          )
        else
          for (final UnitDef u in units)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsetsDirectional.only(
                    start: 14, end: 6, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.surfaces.hairline),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(u.label, style: theme.textTheme.bodyMedium),
                    ),
                    if (u.allowFraction)
                      StatusChip(
                        compact: true,
                        label: context.tr(AppText.itemsAllowFraction),
                        color: AppColors.info,
                      ),
                    const SizedBox(width: 8),
                    StatusChip.neutral(context, '${u.usageCount}'),
                    IconButton(
                      tooltip: context.tr(AppText.delete),
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: AppColors.danger,
                      onPressed: u.usageCount > 0
                          ? null
                          : () async {
                              if (!await confirmDelete(context, what: u.name)) {
                                return;
                              }
                              final bool ok =
                                  await widget.cubit.removeUnit(u.id);
                              if (!mounted) return;
                              if (!ok) {
                                final String? detail =
                                    widget.cubit.state.failure?.detail;
                                if (detail != null) {
                                  AppSnack.error(context, detail);
                                }
                              }
                              setState(() {});
                            },
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
