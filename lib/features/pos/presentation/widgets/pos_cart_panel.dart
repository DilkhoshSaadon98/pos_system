import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/panels.dart';
import '../../../parties/domain/entities/party.dart';
import '../../domain/entities/pos_line.dart';
import '../cubit/pos_cubit.dart';
import '../cubit/pos_state.dart';
import 'line_edit_sheet.dart';


class PosCartPanel extends StatelessWidget {
  const PosCartPanel({
    super.key,
    required this.state,
    required this.onPay,
    required this.onHold,
    required this.onCustomer,
    this.showHeader = true,
  });

  final PosState state;
  final VoidCallback onPay;
  final VoidCallback onHold;
  final VoidCallback onCustomer;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PosCubit cubit = context.read<PosCubit>();
    final SaleTotals totals = state.totals;

    return Column(
      children: <Widget>[
        if (showHeader) _CustomerBar(state: state, onTap: onCustomer),
        Expanded(
          child: state.lines.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message: context.tr(AppText.posCartEmpty),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: state.lines.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: theme.surfaces.hairline),
                  itemBuilder: (BuildContext context, int index) => _CartLine(
                    line: state.lines[index],
                    index: index,
                    selected: state.selectedLine == index,
                    priceMode: state.priceMode,
                  ),
                ),
        ),
        _Totals(totals: totals, state: state),
        _Actions(
          state: state,
          onPay: onPay,
          onHold: onHold,
          onClear: cubit.clearCart,
        ),
      ],
    );
  }
}

class _CustomerBar extends StatelessWidget {
  const _CustomerBar({required this.state, required this.onTap});

  final PosState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Party? customer = state.customer;

    return Material(
      color: theme.surfaces.raised,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 15,
                backgroundColor: (customer == null
                        ? theme.surfaces.muted
                        : AppColors.brand)
                    .withValues(alpha: 0.16),
                child: Icon(
                  customer == null ? Icons.person_outline : Icons.person,
                  size: 17,
                  color: customer == null
                      ? theme.surfaces.muted
                      : AppColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      customer?.name ?? context.tr(AppText.posWalkIn),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer != null && !customer.balance.isZero)
                      Text(
                        '${context.tr(customer.owesUs ? AppText.partiesOwesUs : AppText.partiesWeOwe)}: '
                        '${Fmt.money(customer.balance.abs)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: customer.owesUs
                              ? AppColors.warning
                              : AppColors.ok,
                        ),
                      ),
                  ],
                ),
              ),
              if (customer != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => context.read<PosCubit>().setCustomer(null),
                )
              else
                const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.line,
    required this.index,
    required this.selected,
    required this.priceMode,
  });

  final PosLine line;
  final int index;
  final bool selected;
  final PriceMode priceMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PosCubit cubit = context.read<PosCubit>();
    final int lineTotal = line.isGift ? 0 : line.gross.minor;

    return Dismissible(
      key: ValueKey<String>('${line.item.id}-${line.unit.id}-$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        color: AppColors.danger.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) => cubit.removeLine(index),
      child: Material(
        color: selected ? theme.surfaces.overlay : Colors.transparent,
        child: InkWell(
          onTap: () => cubit.selectLine(index),
          onLongPress: () => showLineEditor(context, cubit, index, line),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              line.item.displayName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (line.isGift) ...<Widget>[
                            const SizedBox(width: 6),
                            StatusChip(
                              compact: true,
                              label: context.tr(AppText.posGift),
                              color: AppColors.accent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          '${Fmt.qty(line.qty)} ${line.unit.unitName}',
                          '× ${Fmt.money(line.unitPrice)}',
                          if (!line.discount.isEmpty)
                            '−${line.discount.kind.name == 'percent' ? Fmt.percentBp(line.discount.value) : Fmt.moneyMinor(line.discount.value)}',
                        ].join('   '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _QtyStepper(index: index, line: line),
                const SizedBox(width: 8),
                SizedBox(
                  width: 86,
                  child: Text(
                    Fmt.moneyMinor(lineTotal, withSymbol: false),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .merge(theme.tabular),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.index, required this.line});

  final int index;
  final PosLine line;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PosCubit cubit = context.read<PosCubit>();


    if (line.item.isWeighed) {
      return OutlinedButton(
        onPressed: () => showLineEditor(context, cubit, index, line),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(Fmt.qty(line.qty)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepButton(
            icon: Icons.remove,
            onTap: () => cubit.bumpQty(index, -1000),
          ),
          SizedBox(
            width: 34,
            child: Text(
              Fmt.qty(line.qty),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: () => cubit.bumpQty(index, 1000),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 17),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.state});

  final SaleTotals totals;
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        border: Border(top: BorderSide(color: theme.surfaces.hairline)),
      ),
      child: Column(
        children: <Widget>[
          TotalRow(
            label:
                '${context.tr(AppText.subtotal)}  ·  ${state.lines.length} ${context.tr(AppText.items).toLowerCase()}',
            value: Fmt.moneyMinor(totals.grossMinor),
          ),
          if (totals.discountTotalMinor > 0)
            TotalRow(
              label: context.tr(AppText.discount),
              value: '−${Fmt.moneyMinor(totals.discountTotalMinor)}',
              color: AppColors.warning,
            ),
          if (totals.taxMinor > 0)
            TotalRow(
              label: context.tr(AppText.tax),
              value: Fmt.moneyMinor(totals.taxMinor),
            ),
          if (totals.serviceChargeMinor > 0)
            TotalRow(
              label: context.tr(AppText.serviceCharge),
              value: Fmt.moneyMinor(totals.serviceChargeMinor),
            ),
          if (totals.roundingMinor != 0)
            TotalRow(
              label: context.tr(AppText.rounding),
              value: Fmt.moneyMinor(totals.roundingMinor),
            ),
          Divider(height: 16, color: theme.surfaces.hairline),
          TotalRow(
            emphasis: true,
            label: context.tr(AppText.total),
            value: Fmt.moneyMinor(totals.totalMinor),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.onPay,
    required this.onHold,
    required this.onClear,
  });

  final PosState state;
  final VoidCallback onPay;
  final VoidCallback onHold;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool has = state.lines.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      color: Theme.of(context).surfaces.raised,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: has ? onHold : null,
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  label: Text(context.tr(AppText.posHold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: has ? onClear : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(context.tr(AppText.posClearCart)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: has && !state.busy ? onPay : null,
              icon: state.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(
                '${context.tr(AppText.posPay)}   ${Fmt.moneyMinor(state.totals.totalMinor)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
