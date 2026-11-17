import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';
import 'item_picker.dart';

/// What a bundle is made of.
///
/// The number at the bottom is the point of this screen: a bundle's cost is the
/// sum of what its parts cost *today*, not a figure somebody typed in when the
/// meal deal was invented. Sell one and the shelf loses each part at its own
/// moving average; the profit on the line is honest without anyone maintaining
/// it.
class BundlePartsEditor extends StatelessWidget {
  const BundlePartsEditor({
    super.key,
    required this.parts,
    required this.onChanged,
    required this.onPick,
    this.sellPrice = Money.zero,
  });

  final List<BundlePart> parts;
  final ValueChanged<List<BundlePart>> onChanged;

  /// Opens the item picker and returns what was chosen.
  final Future<Item?> Function() onPick;

  /// The bundle's own selling price, so the editor can show the margin.
  final Money sellPrice;

  Money get _cost => Money(
        parts.fold(0, (int sum, BundlePart p) => sum + p.lineCost.minor),
      );

  int get _marginBp {
    if (sellPrice.minor <= 0) return 0;
    return ((sellPrice.minor - _cost.minor) * 10000) ~/ sellPrice.minor;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          dense: true,
          title: context.tr(AppText.itemsBundleComponents),
          subtitle: context.tr(AppText.itemsKindBundleHint),
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final Item? picked = await onPick();
                if (picked == null) return;
                if (parts.any((BundlePart p) =>
                    p.componentItemId == picked.id)) {
                  return;
                }
                final ItemUnit? unit = picked.saleUnit;
                onChanged(<BundlePart>[
                  ...parts,
                  BundlePart(
                    componentItemId: picked.id,
                    componentName: picked.displayName,
                    qtyMilli: 1000,
                    itemUnitId: unit?.id,
                    unitName: unit?.unitName ?? picked.baseUnitName,
                    factorMilli: unit?.factorMilli ?? 1000,
                    avgCost: picked.avgCost,
                    sortOrder: parts.length,
                  ),
                ]);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.itemsAddComponent)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (parts.isEmpty)
          EmptyState(
            icon: Icons.widgets_outlined,
            message: context.tr(AppText.itemsKindBundleHint),
            action: FilledButton.icon(
              onPressed: () async {
                final Item? picked = await onPick();
                if (picked == null) return;
                final ItemUnit? unit = picked.saleUnit;
                onChanged(<BundlePart>[
                  BundlePart(
                    componentItemId: picked.id,
                    componentName: picked.displayName,
                    qtyMilli: 1000,
                    itemUnitId: unit?.id,
                    unitName: unit?.unitName ?? picked.baseUnitName,
                    factorMilli: unit?.factorMilli ?? 1000,
                    avgCost: picked.avgCost,
                  ),
                ]);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.itemsAddComponent)),
            ),
          )
        else ...<Widget>[
          for (int i = 0; i < parts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PartRow(
                key: ValueKey<Object>(parts[i].id ?? 'part-$i'),
                part: parts[i],
                onChanged: (BundlePart p) {
                  final List<BundlePart> next = <BundlePart>[...parts];
                  next[i] = p;
                  onChanged(next);
                },
                onRemove: () => onChanged(<BundlePart>[...parts]..removeAt(i)),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.surfaces.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: <Widget>[
                TotalRow(
                  label: context.tr(AppText.itemsBundleCost),
                  value: Fmt.money(_cost),
                ),
                if (sellPrice.isPositive) ...<Widget>[
                  TotalRow(
                    label: context.tr(AppText.itemsSellPrice),
                    value: Fmt.money(sellPrice),
                  ),
                  TotalRow(
                    emphasis: true,
                    label: context.tr(AppText.profit),
                    value:
                        '${Fmt.money(Money(sellPrice.minor - _cost.minor))}  ·  ${Fmt.percentBp(_marginBp)}',
                    color: sellPrice.minor >= _cost.minor
                        ? AppColors.ok
                        : AppColors.danger,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PartRow extends StatefulWidget {
  const _PartRow({
    super.key,
    required this.part,
    required this.onChanged,
    required this.onRemove,
  });

  final BundlePart part;
  final ValueChanged<BundlePart> onChanged;
  final VoidCallback onRemove;

  @override
  State<_PartRow> createState() => _PartRowState();
}

class _PartRowState extends State<_PartRow> {
  late final TextEditingController _qty =
      TextEditingController(text: Fmt.qtyMilli(widget.part.qtyMilli));

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BundlePart p = widget.part;

    return Container(
      padding: const EdgeInsetsDirectional.only(
          start: 14, end: 6, top: 8, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaces.hairline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(p.componentName, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.money(p.avgCost)} / ${p.unitName.isEmpty ? '' : p.unitName}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: context.tr(AppText.qty),
                suffixText: p.unitName,
              ),
              onChanged: (String v) {
                final Qty? q = Fmt.parseQty(v);
                if (q != null && q.milli > 0) {
                  widget.onChanged(p.copyWith(qtyMilli: q.milli));
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              Fmt.money(p.lineCost),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.merge(theme.tabular),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.danger,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

/// The kinds a bundle may contain: plain stocked goods and services. A bundle
/// inside a bundle is refused by the schema, and a variant group is not a thing
/// that can be sold at all.
const Set<ItemKind> bundleComponentKinds = <ItemKind>{
  ItemKind.stock,
  ItemKind.service,
};

/// Convenience wrapper so the form only has to pass a search callback.
Future<Item?> pickBundleComponent(
  BuildContext context,
  Future<List<Item>> Function(String text, {Set<ItemKind>? kinds}) search,
) =>
    showItemPicker(
      context,
      search: (String text) => search(text, kinds: bundleComponentKinds),
      title: AppText.itemsAddComponent,
    );
