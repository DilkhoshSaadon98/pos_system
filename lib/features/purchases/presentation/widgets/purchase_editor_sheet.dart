import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/calc/purchase_calculator.dart';
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
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../catalog/presentation/widgets/item_picker.dart';
import '../../../parties/domain/entities/party.dart';
import '../../domain/entities/purchase_document.dart';
import '../cubit/purchase_editor_cubit.dart';

/// Typing in a delivery.
///
/// The right-hand column is the point of the screen: freight and a supplier
/// discount are spread across the lines by value, so every line shows what a
/// base unit of that item really cost once everything is accounted for. That
/// figure is what enters stock and what every future sale's profit is measured
/// against.
Future<PostedPurchase?> showPurchaseEditor(
  BuildContext context,
  PurchaseEditorCubit cubit,
) =>
    showAppModal<PostedPurchase>(
      context,
      width: 900,
      title: context.tr(AppText.purchaseNew),
      builder: (BuildContext modalContext) => BlocProvider<PurchaseEditorCubit>.value(
        value: cubit,
        child: const _Editor(),
      ),
    );

class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PurchaseEditorCubit, PurchaseEditorState>(
      listenWhen: (PurchaseEditorState a, PurchaseEditorState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, PurchaseEditorState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PurchaseEditorCubit>().clearFailure();
      },
      builder: (BuildContext context, PurchaseEditorState state) {
        final PurchaseEditorCubit cubit = context.read<PurchaseEditorCubit>();
        final PurchaseTotals totals = state.totals;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(state: state, cubit: cubit),
            const SizedBox(height: 16),
            _Lines(state: state, cubit: cubit, totals: totals),
            const SizedBox(height: 16),
            _Footer(state: state, cubit: cubit, totals: totals),
          ],
        );
      },
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.state, required this.cubit});

  final PurchaseEditorState state;
  final PurchaseEditorCubit cubit;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final TextEditingController _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: AppDropdown<int>(
            label: context.tr(AppText.purchaseSupplier),
            prefixIcon: Icons.storefront_outlined,
            value: widget.state.supplier?.id,
            items: widget.state.suppliers.map((Party p) => p.id).toList(),
            itemLabel: (int id) => widget.state.suppliers
                .firstWhere((Party p) => p.id == id)
                .name,
            onChanged: (int? id) => widget.cubit.setSupplier(
              id == null
                  ? null
                  : widget.state.suppliers.firstWhere((Party p) => p.id == id),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: AppTextField(
            controller: _ref,
            label: context.tr(AppText.purchaseRef),
            onChanged: widget.cubit.setSupplierRef,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () async {
            final Item? picked = await showItemPicker(
              context,
              title: AppText.purchaseAddLine,
              search: widget.cubit.lookup,
            );
            if (picked != null) widget.cubit.addItem(picked);
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.tr(AppText.purchaseAddLine)),
        ),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.state,
    required this.cubit,
    required this.totals,
  });

  final PurchaseEditorState state;
  final PurchaseEditorCubit cubit;
  final PurchaseTotals totals;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (state.lines.isEmpty) {
      return Card(
        child: EmptyState(
          icon: Icons.local_shipping_outlined,
          message: context.tr(AppText.purchaseAddLine),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.surfaces.hairline),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < state.lines.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: theme.surfaces.hairline),
            _LineRow(
              key: ValueKey<int>(state.lines[i].item.id),
              index: i,
              line: state.lines[i],
              landed: i < totals.lines.length
                  ? totals.lines[i]
                  : null,
              cubit: cubit,
            ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.index,
    required this.line,
    required this.landed,
    required this.cubit,
  });

  final int index;
  final PurchaseDraftLine line;
  final PurchaseLineTotals? landed;
  final PurchaseEditorCubit cubit;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final TextEditingController _qty =
      TextEditingController(text: Fmt.qty(widget.line.qty));
  late final TextEditingController _cost = TextEditingController(
    text: widget.line.unitCost.isZero
        ? ''
        : Fmt.moneyPlain(widget.line.unitCost.minor),
  );
  late final TextEditingController _sell = TextEditingController(
    text: widget.line.newSellPrice == null
        ? ''
        : Fmt.moneyPlain(widget.line.newSellPrice!.minor),
  );
  late final TextEditingController _batch =
      TextEditingController(text: widget.line.batchNo);

  @override
  void dispose() {
    _batch.dispose();
    _qty.dispose();
    _cost.dispose();
    _sell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PurchaseDraftLine line = widget.line;
    final ItemUnit? unit = line.unit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      line.item.displayName,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${context.tr(AppText.stock)}: '
                      '${Fmt.qtyMilli(line.item.stockQtyMilli)} ${line.item.baseUnitName}'
                      '   ·   ${context.tr(AppText.itemsAvgCost)}: ${Fmt.money(line.item.avgCost)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _qty,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.tr(AppText.qty),
                    suffixText: unit?.unitName,
                  ),
                  onChanged: (String v) {
                    final Qty? q = Fmt.parseQty(v);
                    if (q != null) {
                      widget.cubit.updateLine(
                        widget.index,
                        line.copyWith(qty: q),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _cost,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.tr(AppText.purchaseUnitCost),
                  ),
                  onChanged: (String v) {
                    final Money? m = Fmt.parseMoney(v);
                    if (m != null) {
                      widget.cubit.updateLine(
                        widget.index,
                        line.copyWith(unitCost: m),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _sell,
                  textAlign: TextAlign.end,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.tr(AppText.purchaseNewSellPrice),
                  ),
                  onChanged: (String v) => widget.cubit.updateLine(
                    widget.index,
                    v.trim().isEmpty
                        ? line.copyWith(clearNewSellPrice: true)
                        : line.copyWith(newSellPrice: Fmt.parseMoney(v)),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 19),
                color: AppColors.danger,
                onPressed: () => widget.cubit.removeLine(widget.index),
              ),
            ],
          ),
          // Batch and date, for the goods that have them. Shown only for items
          // set to be counted that way, so a shop that sells hardware never
          // sees a field it has no answer for.
          if (line.wantsBatch) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _batch,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: context.tr(AppText.expiryBatch),
                    ),
                    onChanged: (String v) => widget.cubit.updateLine(
                      widget.index,
                      line.copyWith(batchNo: v.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 17),
                  label: Text(
                    line.expiryDate == null
                        ? context.tr(AppText.expiryDate)
                        : Fmt.date(line.expiryDate!.toIso8601String()),
                  ),
                  onPressed: () async {
                    final DateTime now = DateTime.now();
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: line.expiryDate ??
                          now.add(const Duration(days: 180)),
                      // Goods cannot be received already expired; the data
                      // source refuses it too, but a picker that cannot offer
                      // the wrong answer is better than an error message.
                      firstDate: now,
                      lastDate: DateTime(now.year + 10),
                    );
                    if (picked == null) return;
                    widget.cubit.updateLine(
                      widget.index,
                      line.copyWith(expiryDate: picked),
                    );
                  },
                ),
                if (line.expiryDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 17),
                    onPressed: () => widget.cubit.updateLine(
                      widget.index,
                      line.copyWith(clearExpiry: true),
                    ),
                  ),
              ],
            ),
          ],

          if (widget.landed != null) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                if (line.item.units.length > 1) ...<Widget>[
                  for (final ItemUnit u in line.item.units)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(u.unitName),
                        selected: u.id == unit?.id,
                        onSelected: (_) => widget.cubit.updateLine(
                          widget.index,
                          line.copyWith(unit: u),
                        ),
                      ),
                    ),
                ],
                const Spacer(),
                StatusChip(
                  compact: true,
                  icon: Icons.local_shipping_outlined,
                  label:
                      '${context.tr(AppText.purchaseLandedCost)}: ${Fmt.moneyMinor(widget.landed!.landedUnitCostMinor)} / ${line.item.baseUnitName}',
                  color: AppColors.info,
                ),
                const SizedBox(width: 10),
                Text(
                  Fmt.moneyMinor(widget.landed!.landedTotalMinor),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700)
                      .merge(theme.tabular),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatefulWidget {
  const _Footer({
    required this.state,
    required this.cubit,
    required this.totals,
  });

  final PurchaseEditorState state;
  final PurchaseEditorCubit cubit;
  final PurchaseTotals totals;

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  final TextEditingController _fees = TextEditingController();
  final TextEditingController _paid = TextEditingController();

  @override
  void dispose() {
    _fees.dispose();
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PurchaseTotals t = widget.totals;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MoneyField(
                controller: _fees,
                label: context.tr(AppText.purchaseFees),
                helper: context.tr(AppText.purchaseFeesHint),
                onChanged: (Money? m) =>
                    widget.cubit.setFees(m ?? Money.zero),
              ),
              const SizedBox(height: 12),
              DiscountField(
                value: widget.state.invoiceDiscount,
                label: context.tr(AppText.discount),
                onChanged: widget.cubit.setInvoiceDiscount,
              ),
              const SizedBox(height: 12),
              AppSwitchTile(
                icon: Icons.sell_outlined,
                title: context.tr(AppText.purchaseUpdatePrices),
                value: widget.state.updateSellPrices,
                onChanged: widget.cubit.setUpdateSellPrices,
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 340,
          child: Column(
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
                    TotalRow(
                      label: context.tr(AppText.gross),
                      value: Fmt.moneyMinor(t.grossMinor),
                    ),
                    if (t.discountTotalMinor > 0)
                      TotalRow(
                        label: context.tr(AppText.discount),
                        value: '−${Fmt.moneyMinor(t.discountTotalMinor)}',
                        color: AppColors.warning,
                      ),
                    if (t.feesMinor > 0)
                      TotalRow(
                        label: context.tr(AppText.purchaseFees),
                        value: Fmt.moneyMinor(t.feesMinor),
                      ),
                    if (t.taxMinor > 0)
                      TotalRow(
                        label: context.tr(AppText.tax),
                        value: Fmt.moneyMinor(t.taxMinor),
                      ),
                    Divider(height: 16, color: theme.surfaces.hairline),
                    TotalRow(
                      emphasis: true,
                      label: context.tr(AppText.total),
                      value: Fmt.moneyMinor(t.totalMinor),
                    ),
                    TotalRow(
                      label: context.tr(AppText.itemsStockValue),
                      value: Fmt.moneyMinor(t.inventoryValueMinor),
                      icon: Icons.inventory_2_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MoneyField(
                controller: _paid,
                label: context.tr(AppText.purchasePayNow),
                onChanged: (Money? m) =>
                    widget.cubit.setPaid(m ?? Money.zero),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () {
                      widget.cubit.payAll();
                      _paid.text = Fmt.moneyPlain(t.totalMinor);
                    },
                    child: Text(context.tr(AppText.all)),
                  ),
                  const Spacer(),
                  Text(
                    '${context.tr(AppText.due)}: ${Fmt.moneyMinor(t.dueMinor)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.dueMinor > 0 ? AppColors.warning : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AppDropdown<String>(
                label: context.tr(AppText.method),
                value: widget.state.paymentMethodKey,
                items: const <String>[
                  AccountKeys.cash,
                  AccountKeys.bank,
                  AccountKeys.card,
                ],
                itemLabel: (String key) => context.tr(switch (key) {
                  AccountKeys.bank => AppText.bank,
                  AccountKeys.card => AppText.card,
                  _ => AppText.cash,
                }),
                onChanged: (String? v) =>
                    widget.cubit.setPaymentMethod(v ?? AccountKeys.cash),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: widget.state.canPost && !widget.state.busy
                      ? () => _post(context)
                      : null,
                  icon: widget.state.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(context.tr(AppText.save)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _post(BuildContext context) async {
    final bool ok = await confirm(
      context,
      icon: Icons.local_shipping_outlined,
      destructive: false,
      title: context.tr(AppText.purchaseNew),
      message: context.tr(AppText.purchaseSaveConfirm),
      confirmLabel: context.tr(AppText.save),
    );
    if (!ok || !context.mounted) return;

    final int? userId = context.read<AuthCubit>().state.user?.id;
    final PostedPurchase? posted = await widget.cubit.post(userId: userId);
    if (!context.mounted || posted == null) return;

    AppSnack.success(
      context,
      '${context.tr(AppText.purchaseSaved)} — ${posted.invoiceNo}',
    );
    Navigator.of(context).pop(posted);
  }
}
