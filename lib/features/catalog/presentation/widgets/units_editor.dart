import 'package:flutter/material.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';

/// Units and prices for one item.
///
/// This is the part of the app that makes "buy a carton, sell a piece" work, so
/// it is worth being explicit about the model. An item has exactly one **base**
/// unit — the thing stock is counted in — and any number of larger units, each
/// carrying how many base units it holds, its own prices and its own barcode.
/// A carton of twelve pieces is a factor of 12; the piece is the base and is
/// always 1.
///
/// Everything else in the system follows from that one number: the till
/// converts a carton into twelve pieces before touching stock, a purchase
/// divides the carton's landed cost by twelve to get the cost of a piece, and a
/// scan of the carton barcode adds a carton at the carton price.
class UnitsEditor extends StatelessWidget {
  const UnitsEditor({
    super.key,
    required this.rows,
    required this.available,
    required this.onChanged,
    this.avgCost = Money.zero,
  });

  final List<ItemUnit> rows;
  final List<UnitDef> available;
  final ValueChanged<List<ItemUnit>> onChanged;

  /// Shown beside each price as a live margin, so a shopkeeper pricing a new
  /// delivery can see what they are making without leaving the form.
  final Money avgCost;

  void _update(int index, ItemUnit unit) {
    final List<ItemUnit> next = <ItemUnit>[...rows];
    next[index] = unit;
    onChanged(next);
  }

  void _makeBase(int index) {
    final List<ItemUnit> next = <ItemUnit>[
      for (int i = 0; i < rows.length; i++)
        rows[i].copyWith(
          isBase: i == index,
          // The base unit is the yardstick: it always contains exactly one of
          // itself, so setting it fixes the factor at the same moment.
          factorMilli: i == index ? 1000 : rows[i].factorMilli,
        ),
    ];
    onChanged(next);
  }

  void _setDefault(int index, {required bool forSale}) {
    final List<ItemUnit> next = <ItemUnit>[
      for (int i = 0; i < rows.length; i++)
        forSale
            ? rows[i].copyWith(isDefaultSale: i == index)
            : rows[i].copyWith(isDefaultPurchase: i == index),
    ];
    onChanged(next);
  }

  void _add(BuildContext context) {
    final Set<int> used = rows.map((ItemUnit u) => u.unitId).toSet();
    UnitDef? free;
    for (final UnitDef u in available) {
      if (!used.contains(u.id)) {
        free = u;
        break;
      }
    }
    if (free == null) return;

    onChanged(<ItemUnit>[
      ...rows,
      ItemUnit(
        id: null,
        itemId: 0,
        unitId: free.id,
        unitName: free.name,
        factorMilli: rows.isEmpty ? 1000 : 1000,
        sellPrice: Money.zero,
        wholesalePrice: Money.zero,
        minPrice: Money.zero,
        isBase: rows.isEmpty,
        isDefaultSale: rows.isEmpty,
        isDefaultPurchase: rows.isEmpty,
        sortOrder: rows.length,
      ),
    ]);
  }

  void _remove(int index) {
    final List<ItemUnit> next = <ItemUnit>[...rows]..removeAt(index);
    // Never leave the item without a base unit or without a default: the first
    // remaining row takes over, which is what the shopkeeper would have done.
    if (next.isNotEmpty) {
      if (!next.any((ItemUnit u) => u.isBase)) {
        next[0] = next[0].copyWith(isBase: true, factorMilli: 1000);
      }
      if (!next.any((ItemUnit u) => u.isDefaultSale)) {
        next[0] = next[0].copyWith(isDefaultSale: true);
      }
      if (!next.any((ItemUnit u) => u.isDefaultPurchase)) {
        next[0] = next[0].copyWith(isDefaultPurchase: true);
      }
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final Set<int> used = rows.map((ItemUnit u) => u.unitId).toSet();
    final bool canAdd = available.any((UnitDef u) => !used.contains(u.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          dense: true,
          title: context.tr(AppText.itemsUnitsTitle),
          subtitle: context.tr(AppText.itemsFactor),
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: canAdd ? () => _add(context) : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.itemsAddUnit)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          EmptyState(
            icon: Icons.straighten_outlined,
            message: context.tr(AppText.itemsNoUnitsYet),
            action: FilledButton.icon(
              onPressed: canAdd ? () => _add(context) : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.itemsAddUnit)),
            ),
          )
        else
          for (int i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _UnitRow(
                key: ValueKey<Object>(rows[i].id ?? 'new-$i'),
                unit: rows[i],
                available: available,
                taken: used,
                avgCost: avgCost,
                canRemove: rows.length > 1,
                onChanged: (ItemUnit u) => _update(i, u),
                onMakeBase: () => _makeBase(i),
                onDefaultSale: () => _setDefault(i, forSale: true),
                onDefaultPurchase: () => _setDefault(i, forSale: false),
                onRemove: () => _remove(i),
              ),
            ),
      ],
    );
  }
}

class _UnitRow extends StatefulWidget {
  const _UnitRow({
    super.key,
    required this.unit,
    required this.available,
    required this.taken,
    required this.avgCost,
    required this.canRemove,
    required this.onChanged,
    required this.onMakeBase,
    required this.onDefaultSale,
    required this.onDefaultPurchase,
    required this.onRemove,
  });

  final ItemUnit unit;
  final List<UnitDef> available;
  final Set<int> taken;
  final Money avgCost;
  final bool canRemove;
  final ValueChanged<ItemUnit> onChanged;
  final VoidCallback onMakeBase;
  final VoidCallback onDefaultSale;
  final VoidCallback onDefaultPurchase;
  final VoidCallback onRemove;

  @override
  State<_UnitRow> createState() => _UnitRowState();
}

class _UnitRowState extends State<_UnitRow> {
  late final TextEditingController _factor =
      TextEditingController(text: Fmt.qtyMilli(widget.unit.factorMilli));
  late final TextEditingController _sell = TextEditingController(
      text: widget.unit.sellPrice.isZero
          ? ''
          : Fmt.moneyPlain(widget.unit.sellPrice.minor));
  late final TextEditingController _wholesale = TextEditingController(
      text: widget.unit.wholesalePrice.isZero
          ? ''
          : Fmt.moneyPlain(widget.unit.wholesalePrice.minor));
  late final TextEditingController _min = TextEditingController(
      text: widget.unit.minPrice.isZero
          ? ''
          : Fmt.moneyPlain(widget.unit.minPrice.minor));
  late final TextEditingController _barcode =
      TextEditingController(text: widget.unit.barcode ?? '');

  @override
  void dispose() {
    _factor.dispose();
    _sell.dispose();
    _wholesale.dispose();
    _min.dispose();
    _barcode.dispose();
    super.dispose();
  }

  /// The cost of one of *this* unit, from the item's cost per base unit.
  Money get _unitCost =>
      Money((widget.avgCost.minor * widget.unit.factorMilli) ~/ 1000);

  int get _marginBp {
    final int price = widget.unit.sellPrice.minor;
    if (price <= 0) return 0;
    return ((price - _unitCost.minor) * 10000) ~/ price;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ItemUnit u = widget.unit;
    final List<UnitDef> choices = widget.available
        .where((UnitDef d) => d.id == u.unitId || !widget.taken.contains(d.id))
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: u.isBase ? theme.surfaces.raised : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: u.isBase
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.surfaces.hairline,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: AppDropdown<int>(
                  label: context.tr(AppText.unit),
                  value: u.unitId,
                  items: choices.map((UnitDef d) => d.id).toList(),
                  itemLabel: (int id) => choices
                      .firstWhere((UnitDef d) => d.id == id,
                          orElse: () => choices.first)
                      .label,
                  onChanged: (int? id) {
                    if (id == null) return;
                    final UnitDef def =
                        choices.firstWhere((UnitDef d) => d.id == id);
                    widget.onChanged(
                      u.copyWith(unitId: def.id, unitName: def.name),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: _factor,
                  label: context.tr(AppText.itemsFactor),
                  enabled: !u.isBase,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (String v) {
                    final Qty? q = Fmt.parseQty(v);
                    if (q != null && q.milli > 0) {
                      widget.onChanged(u.copyWith(factorMilli: q.milli));
                    }
                  },
                ),
              ),
              if (widget.canRemove) ...<Widget>[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: context.tr(AppText.remove),
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.danger,
                  onPressed: widget.onRemove,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: MoneyField(
                  controller: _sell,
                  label: context.tr(AppText.itemsSellPrice),
                  helper: widget.avgCost.isPositive && u.sellPrice.isPositive
                      ? '${context.tr(AppText.itemsMargin)} ${Fmt.percentBp(_marginBp)}'
                      : null,
                  onChanged: (Money? m) =>
                      widget.onChanged(u.copyWith(sellPrice: m ?? Money.zero)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MoneyField(
                  controller: _wholesale,
                  label: context.tr(AppText.itemsWholesalePrice),
                  onChanged: (Money? m) => widget
                      .onChanged(u.copyWith(wholesalePrice: m ?? Money.zero)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: MoneyField(
                  controller: _min,
                  label: context.tr(AppText.itemsMinPrice),
                  onChanged: (Money? m) =>
                      widget.onChanged(u.copyWith(minPrice: m ?? Money.zero)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  controller: _barcode,
                  label: context.tr(AppText.barcode),
                  prefixIcon: Icons.qr_code_2,
                  onChanged: (String v) => widget.onChanged(
                    v.trim().isEmpty
                        ? u.copyWith(clearBarcode: true)
                        : u.copyWith(barcode: v.trim()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Flag(
                label: context.tr(AppText.itemsBaseUnit),
                selected: u.isBase,
                onTap: widget.onMakeBase,
              ),
              _Flag(
                label: context.tr(AppText.itemsDefaultSale),
                selected: u.isDefaultSale,
                onTap: widget.onDefaultSale,
              ),
              _Flag(
                label: context.tr(AppText.itemsDefaultPurchase),
                selected: u.isDefaultPurchase,
                onTap: widget.onDefaultPurchase,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}
