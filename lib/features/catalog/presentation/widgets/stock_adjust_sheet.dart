import 'package:flutter/material.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';
import '../cubit/items_cubit.dart';

/// Correcting stock after a count.
///
/// The figure typed here is what is **on the shelf**, not the difference — that
/// is how a person counts. The app works out the difference, writes it as one
/// adjustment movement valued at the current average, and posts the same amount
/// to the books, so the inventory account never drifts away from the stock it
/// is supposed to represent. The old app changed the number and left the ledger
/// alone, which is how its balance sheet stopped meaning anything.
Future<void> showStockAdjust(
  BuildContext context,
  ItemsCubit cubit,
  Item item,
) =>
    showAppModal<void>(
      context,
      width: 480,
      title: context.tr(AppText.stockAdjust),
      subtitle: item.displayName,
      builder: (BuildContext context) => _StockAdjust(cubit: cubit, item: item),
    );

class _StockAdjust extends StatefulWidget {
  const _StockAdjust({required this.cubit, required this.item});

  final ItemsCubit cubit;
  final Item item;

  @override
  State<_StockAdjust> createState() => _StockAdjustState();
}

class _StockAdjustState extends State<_StockAdjust> {
  late final TextEditingController _counted =
      TextEditingController(text: Fmt.qtyMilli(widget.item.stockQtyMilli));
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  int _countedMilli = 0;

  @override
  void initState() {
    super.initState();
    _countedMilli = widget.item.stockQtyMilli;
  }

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _difference => _countedMilli - widget.item.stockQtyMilli;

  Money get _value =>
      Money((widget.item.avgCost.minor * _difference) ~/ 1000);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                label: context.tr(AppText.stock),
                value:
                    '${Fmt.qtyMilli(widget.item.stockQtyMilli)} ${widget.item.baseUnitName}',
              ),
              TotalRow(
                label: context.tr(AppText.itemsAvgCost),
                value: Fmt.money(widget.item.avgCost),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        QtyField(
          controller: _counted,
          autofocus: true,
          label: context.tr(AppText.itemsCountedQty),
          unitName: widget.item.baseUnitName,
          onChanged: (Qty? q) =>
              setState(() => _countedMilli = q?.milli ?? _countedMilli),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: context.tr(AppText.note),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (_difference == 0
                    ? theme.surfaces.muted
                    : _difference > 0
                        ? AppColors.ok
                        : AppColors.danger)
                .withValues(alpha: theme.isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                label: context.tr(AppText.stockDifference),
                value:
                    '${_difference > 0 ? '+' : ''}${Fmt.qtyMilli(_difference)} ${widget.item.baseUnitName}',
                color: AppColors.forAmount(_difference),
              ),
              TotalRow(
                emphasis: true,
                label: context.tr(AppText.value),
                value: Fmt.money(_value),
                color: AppColors.forAmount(_value.minor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ModalActions(
          busy: _busy,
          saveLabel: context.tr(AppText.stockAdjust),
          onSave: _difference == 0 ? null : _apply,
        ),
      ],
    );
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final bool ok = await widget.cubit.adjustStock(
      itemId: widget.item.id,
      counted: Qty(_countedMilli),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      AppSnack.success(context, context.tr(AppText.saved));
      Navigator.of(context).pop();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}
