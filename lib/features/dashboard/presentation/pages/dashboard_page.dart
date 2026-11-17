import 'package:cashier_system_v2/features/dashboard/presentation/cubit/dashboard_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../cubit/dashboard_cubit.dart';


class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (BuildContext context, DashboardState state) {
        final DashboardCubit cubit = context.read<DashboardCubit>();
        final DashboardSnapshot s = state.snapshot;

        if (state.status.isBusyFirstTime) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status.isFailure && state.failure != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorNotice(failure: state.failure!, onRetry: cubit.load),
          );
        }

        return RefreshIndicator(
          onRefresh: cubit.load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              20,
              Responsive.isMobile(context) ? 14 : 24,
              40,
            ),
            children: <Widget>[
              SectionHeader(
                title: Fmt.dayName(state.day),
                subtitle: context.tr(AppText.appSubtitle),
                actions: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: state.day,
                        firstDate: DateTime(DateTime.now().year - 5),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) await cubit.load(day: picked);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(context.tr(AppText.date)),
                  ),
                  OutlinedButton.icon(
                    onPressed: cubit.load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.tr(AppText.refresh)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Kpis(snapshot: s),
              const SizedBox(height: 18),
              if (Responsive.isCompact(context)) ...<Widget>[
                _SalesChart(snapshot: s),
                const SizedBox(height: 16),
                _TopItems(snapshot: s),
                const SizedBox(height: 16),
                _LowStock(snapshot: s),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 3, child: _SalesChart(snapshot: s)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _TopItems(snapshot: s)),
                  ],
                ),
              if (!Responsive.isCompact(context)) ...<Widget>[
                const SizedBox(height: 16),
                _LowStock(snapshot: s),
              ],
              if (!s.inventoryGap.isZero) ...<Widget>[
                const SizedBox(height: 16),
                _GapNotice(gap: s.inventoryGap),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 560
            ? 2
            : constraints.maxWidth < 1000
                ? 3
                : 4;
        const double gap = 12;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final List<Widget> cards = <Widget>[
          KpiCard(
            icon: Icons.point_of_sale_outlined,
            label: context.tr(AppText.dashTodaySales),
            value: Fmt.money(snapshot.salesToday),
            footnote:
                '${snapshot.invoicesToday}  ${context.tr(AppText.dashInvoices).toLowerCase()}',
          ),
          KpiCard(
            icon: Icons.trending_up,
            label: context.tr(AppText.dashTodayProfit),
            value: Fmt.money(snapshot.profitToday),
            tint: AppColors.accent,
          ),
          KpiCard(
            icon: Icons.savings_outlined,
            label: context.tr(AppText.dashCashBalance),
            value: Fmt.money(snapshot.cash),
            tint: AppColors.ok,
            footnote:
                '${context.tr(AppText.dashBankBalance)}: ${Fmt.money(snapshot.bank)}',
          ),
          KpiCard(
            icon: Icons.inventory_2_outlined,
            label: context.tr(AppText.dashStockValue),
            value: Fmt.money(snapshot.stockValue),
            tint: AppColors.info,
            footnote:
                '${snapshot.lowStockCount} ${context.tr(AppText.dashLowStockItems).toLowerCase()}',
          ),
          KpiCard(
            icon: Icons.call_received,
            label: context.tr(AppText.dashReceivables),
            value: Fmt.money(snapshot.receivable),
            tint: AppColors.warning,
          ),
          KpiCard(
            icon: Icons.call_made,
            label: context.tr(AppText.dashPayables),
            value: Fmt.money(snapshot.payable),
            tint: AppColors.danger,
          ),
          KpiCard(
            icon: Icons.schedule_outlined,
            label: context.tr(AppText.dashCreditSales),
            value: Fmt.money(snapshot.creditToday),
          ),
          KpiCard(
            icon: Icons.production_quantity_limits,
            label: context.tr(AppText.dashOutOfStock),
            value: '${snapshot.outOfStockCount}',
            tint: AppColors.danger,
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget card in cards)
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}


class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int peak = snapshot.seriesPeak;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              dense: true,
              title: context.tr(AppText.dashLast14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 170,
              child: snapshot.dailySeries.isEmpty
                  ? EmptyState(
                      icon: Icons.bar_chart_outlined,
                      message: context.tr(AppText.nothingYet),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (final DailyPoint p in snapshot.dailySeries)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${p.day}\n${Fmt.money(p.total)}\n${context.tr(AppText.profit)}: ${Fmt.money(p.profit)}',
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    Container(
                                      height: (140 * (p.total.minor / peak))
                                          .clamp(3, 140)
                                          .toDouble(),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.85),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      p.day.length >= 10
                                          ? p.day.substring(8)
                                          : p.day,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopItems extends StatelessWidget {
  const _TopItems({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(dense: true, title: context.tr(AppText.dashTopItems)),
            const SizedBox(height: 12),
            if (snapshot.topItems.isEmpty)
              EmptyState(
                icon: Icons.emoji_events_outlined,
                message: context.tr(AppText.nothingYet),
              )
            else
              for (final TopItem item in snapshot.topItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        Fmt.qtyMilli(item.qtyMilli),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        Fmt.money(item.total),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)
                            .merge(theme.tabular),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              dense: true,
              title: context.tr(AppText.dashLowStockItems),
            ),
            const SizedBox(height: 12),
            if (snapshot.lowStock.isEmpty)
              EmptyState(
                icon: Icons.verified_outlined,
                message: context.tr(AppText.nothingYet),
              )
            else
              for (final LowStockItem item in snapshot.lowStock)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 4,
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.fraction,
                            minHeight: 7,
                            backgroundColor: theme.surfaces.raised,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              item.qtyMilli <= 0
                                  ? AppColors.danger
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '${Fmt.qtyMilli(item.qtyMilli)} / ${Fmt.qtyMilli(item.reorderMilli)} ${item.unitName}',
                        style: theme.textTheme.bodySmall?.merge(theme.tabular),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _GapNotice extends StatelessWidget {
  const _GapNotice({required this.gap});

  final Money gap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            const Icon(Icons.rule_outlined, color: AppColors.warning),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${context.tr(AppText.dashInventoryGap)}: ${Fmt.money(gap)}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(AppText.dashInventoryGapHint),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
