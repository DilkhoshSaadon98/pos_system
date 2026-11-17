import 'package:flutter/material.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';

/// The variant matrix for a product sold in several sizes, colours or flavours.
///
/// The shopkeeper describes what varies — `Size: S, M, L` — and the app builds
/// the combinations. Each combination becomes a real item with its own stock,
/// its own cost and its own barcode, because that is what a shirt in a size
/// actually is: a thing you can count on a shelf. The group above them is never
/// sold; it exists so the till can offer a picker instead of twelve tiles.
class VariantAxesEditor extends StatelessWidget {
  const VariantAxesEditor({
    super.key,
    required this.axes,
    required this.onChanged,
    required this.variants,
    this.onGenerate,
    this.busy = false,
  });

  final List<VariantAxis> axes;
  final ValueChanged<List<VariantAxis>> onChanged;

  /// The variants that already exist, so the editor can say what generating
  /// would add rather than leaving it a surprise.
  final List<Item> variants;

  final VoidCallback? onGenerate;
  final bool busy;

  int get _combinations => axes.isEmpty
      ? 0
      : axes.fold(1, (int total, VariantAxis a) => total * a.values.length);

  int get _missing {
    final int total = _combinations;
    final int have = variants.length;
    return total <= have ? 0 : total - have;
  }

  void _update(int index, VariantAxis axis) {
    final List<VariantAxis> next = <VariantAxis>[...axes];
    next[index] = axis;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          dense: true,
          title: context.tr(AppText.itemsVariantAxes),
          subtitle: context.tr(AppText.itemsAxisValuesHint),
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => onChanged(<VariantAxis>[
                ...axes,
                VariantAxis(
                  name: '',
                  values: const <String>[],
                  sortOrder: axes.length,
                ),
              ]),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.add)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < axes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AxisRow(
              key: ValueKey<Object>(axes[i].id ?? 'axis-$i'),
              axis: axes[i],
              onChanged: (VariantAxis a) => _update(i, a),
              onRemove: () => onChanged(
                <VariantAxis>[...axes]..removeAt(i),
              ),
            ),
          ),
        if (axes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.surfaces.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$_combinations  ${context.tr(AppText.itemsVariants).toLowerCase()}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _missing == 0
                            ? context.tr(AppText.itemsVariants)
                            : '+$_missing',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: busy || onGenerate == null || _missing == 0
                      ? null
                      : onGenerate,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_motion_outlined, size: 18),
                  label: Text(context.tr(AppText.itemsGenerateVariants)),
                ),
              ],
            ),
          ),
        ],
        if (variants.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(dense: true, title: context.tr(AppText.itemsVariants)),
          const SizedBox(height: 10),
          for (final Item v in variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.surfaces.hairline),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        v.variantName ?? v.name,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      Fmt.money(v.defaultSellPrice),
                      style: theme.textTheme.bodyMedium?.merge(theme.tabular),
                    ),
                    const SizedBox(width: 14),
                    StatusChip(
                      compact: true,
                      label:
                          '${Fmt.qtyMilli(v.stockQtyMilli)} ${v.baseUnitName}',
                      color: v.isOutOfStock
                          ? AppColors.danger
                          : v.isLowStock
                              ? AppColors.warning
                              : AppColors.ok,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AxisRow extends StatefulWidget {
  const _AxisRow({
    super.key,
    required this.axis,
    required this.onChanged,
    required this.onRemove,
  });

  final VariantAxis axis;
  final ValueChanged<VariantAxis> onChanged;
  final VoidCallback onRemove;

  @override
  State<_AxisRow> createState() => _AxisRowState();
}

class _AxisRowState extends State<_AxisRow> {
  late final TextEditingController _name =
      TextEditingController(text: widget.axis.name);
  late final TextEditingController _values =
      TextEditingController(text: widget.axis.values.join(', '));

  @override
  void dispose() {
    _name.dispose();
    _values.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: AppTextField(
            controller: _name,
            label: context.tr(AppText.itemsAxisName),
            onChanged: (String v) =>
                widget.onChanged(widget.axis.copyWith(name: v)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: AppTextField(
            controller: _values,
            label: context.tr(AppText.itemsAxisValues),
            hint: 'S, M, L, XL',
            onChanged: (String v) => widget.onChanged(
              widget.axis.copyWith(
                values: v
                    .split(',')
                    .map((String s) => s.trim())
                    .where((String s) => s.isNotEmpty)
                    .toList(growable: false),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.danger,
            onPressed: widget.onRemove,
          ),
        ),
      ],
    );
  }
}
