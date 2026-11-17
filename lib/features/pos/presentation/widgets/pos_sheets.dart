import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/number_pad.dart';
import '../../../../core/widgets/panels.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../parties/domain/entities/party.dart';
import '../../domain/entities/pos_line.dart';


Future<Item?> showVariantPicker(
  BuildContext context, {
  required Item group,
  required List<Item> variants,
  required PriceMode priceMode,
}) =>
    showAppModal<Item>(
      context,
      width: 520,
      title: context.tr(AppText.posChooseVariant),
      subtitle: group.name,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final Item v in variants)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: v.isOutOfStock && !v.allowNegative
                        ? null
                        : () => Navigator.of(context).pop(v),
                    child: Opacity(
                      opacity: v.isOutOfStock && !v.allowNegative ? 0.45 : 1,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: theme.surfaces.hairline),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    v.variantName ?? v.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (v.variantAttrs.isNotEmpty)
                                    Text(
                                      v.variantAttrs.entries
                                          .map((MapEntry<String, String> e) =>
                                              '${e.key}: ${e.value}')
                                          .join('   ·   '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
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
                            const SizedBox(width: 12),
                            Text(
                              Fmt.money(
                                v.saleUnit?.priceFor(priceMode) ??
                                    v.defaultSellPrice,
                              ),
                              style: theme.textTheme.titleSmall
                                  ?.merge(theme.tabular),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );


Future<Qty?> showWeighSheet(
  BuildContext context, {
  required Item item,
  required ItemUnit? unit,
}) =>
    showAppModal<Qty>(
      context,
      width: 420,
      title: item.displayName,
      subtitle: context.tr(AppText.posWeighHint),
      builder: (BuildContext context) => _WeighBody(item: item, unit: unit),
    );

class _WeighBody extends StatefulWidget {
  const _WeighBody({required this.item, required this.unit});

  final Item item;
  final ItemUnit? unit;

  @override
  State<_WeighBody> createState() => _WeighBodyState();
}

class _WeighBodyState extends State<_WeighBody> {
  final PadBuffer _pad = PadBuffer();

  Qty get _qty => Fmt.parseQty(_pad.text) ?? Qty.zero;

  Money get _price => widget.unit?.sellPrice ?? widget.item.defaultSellPrice;

  int get _amount => (_price.minor * _qty.milli) ~/ 1000;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(context.tr(AppText.posWeigh),
                      style: theme.textTheme.bodySmall),
                  const Spacer(),
                  Text(
                    _pad.text.isEmpty ? '0' : _pad.text,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .merge(theme.tabular),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.unit?.unitName ?? widget.item.baseUnitName,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              Divider(height: 20, color: theme.surfaces.hairline),
              TotalRow(
                label:
                    '${Fmt.money(_price)} / ${widget.unit?.unitName ?? widget.item.baseUnitName}',
                value: Fmt.moneyMinor(_amount),
                emphasis: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        NumberPad(
          onDigit: (String d) => setState(() => _pad.digit(d)),
          onBackspace: () => setState(_pad.backspace),
          onClear: () => setState(_pad.clear),
        ),
        const SizedBox(height: 18),
        ModalActions(
          saveLabel: context.tr(AppText.add),
          onSave: _qty.isPositive
              ? () => Navigator.of(context).pop(_qty)
              : null,
        ),
      ],
    );
  }
}

Future<int?> showHeldCarts(
  BuildContext context, {
  required List<HeldCart> carts,
  required void Function(int cartId) onDiscard,
}) =>
    showAppModal<int>(
      context,
      width: 480,
      title: context.tr(AppText.posHeldCarts),
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        if (carts.isEmpty) {
          return EmptyState(
            icon: Icons.pause_circle_outline,
            message: context.tr(AppText.nothingYet),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final HeldCart cart in carts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsetsDirectional.only(
                      start: 14, end: 6, top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: theme.surfaces.hairline),
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppColors.brand.withValues(alpha: 0.15),
                        child: Text(
                          '${cart.slotNo}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              cart.label ??
                                  cart.partyName ??
                                  context.tr(
                                    AppText.posSlot,
                                    params: <String, Object?>{'n': cart.slotNo},
                                  ),
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              '${context.tr(AppText.posLines, params: <String, Object?>{'n': cart.lineCount})}'
                              '  ·  ${Fmt.dateTime(cart.createdAt)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(cart.id),
                        child: Text(context.tr(AppText.posResume)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 19),
                        color: AppColors.danger,
                        onPressed: () async {
                          if (await confirmDelete(context)) {
                            onDiscard(cart.id);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );

//? Who is buying — with their balance, so a cashier can see at a glance whether
Future<Party?> showCustomerPicker(
  BuildContext context, {
  required List<Party> customers,
}) =>
    showAppModal<Party>(
      context,
      width: 480,
      title: context.tr(AppText.posPickCustomer),
      builder: (BuildContext context) => _CustomerPicker(customers: customers),
    );

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.customers});

  final List<Party> customers;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String q = _query.trim().toLowerCase();
    final List<Party> shown = q.isEmpty
        ? widget.customers
        : widget.customers
            .where((Party p) =>
                p.name.toLowerCase().contains(q) ||
                (p.phone ?? '').contains(q))
            .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          autofocus: true,
          onChanged: (String v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: context.tr(AppText.search),
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(context.tr(AppText.posWalkIn)),
          onTap: () => Navigator.of(context).pop(),
        ),
        Divider(color: theme.surfaces.hairline),
        SizedBox(
          height: 320,
          child: shown.isEmpty
              ? EmptyState(
                  icon: Icons.person_search_outlined,
                  message: context.tr(AppText.noResults),
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Party p = shown[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(p.phone ?? ''),
                      trailing: p.balance.isZero
                          ? null
                          : StatusChip(
                              compact: true,
                              label: Fmt.money(p.balance.abs),
                              color: p.owesUs
                                  ? AppColors.warning
                                  : AppColors.ok,
                            ),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
