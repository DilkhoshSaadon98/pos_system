import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/panels.dart';
import 'insights_feature.dart';

class InsightsState {
  const InsightsState({
    this.status = AppStatus.initial,
    this.snapshot,
    this.deadAfterDays = 60,
    this.tab = 0,
    this.failure,
  });

  final AppStatus status;
  final InsightsSnapshot? snapshot;
  final int deadAfterDays;
  final int tab;
  final Failure? failure;

  InsightsState copyWith({
    AppStatus? status,
    InsightsSnapshot? snapshot,
    int? deadAfterDays,
    int? tab,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      InsightsState(
        status: status ?? this.status,
        snapshot: snapshot ?? this.snapshot,
        deadAfterDays: deadAfterDays ?? this.deadAfterDays,
        tab: tab ?? this.tab,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class InsightsCubit extends Cubit<InsightsState> {
  InsightsCubit(this._repository) : super(const InsightsState());

  final InsightsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));
    final Result<InsightsSnapshot> result =
        await _repository.load(deadAfterDays: state.deadAfterDays);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            snapshot: result.valueOrNull,
            clearFailure: true,
          ));
  }

  void setTab(int tab) => emit(state.copyWith(tab: tab));

  Future<void> setDeadAfter(int days) {
    emit(state.copyWith(deadAfterDays: days));
    return load();
  }
}

/// The four questions worth asking at the end of a month.
///
/// Deliberately not a wall of charts. Each tab answers one question and ends
/// in a list a shopkeeper can act on the same afternoon: buy this, stop buying
/// that, put someone on the till at five.
class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InsightsCubit, InsightsState>(
      builder: (BuildContext context, InsightsState state) {
        final InsightsCubit cubit = context.read<InsightsCubit>();
        final bool mobile = Responsive.isMobile(context);
        final InsightsSnapshot? snap = state.snapshot;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.insightsTitle),
                subtitle: context.tr(AppText.insightsSubtitle),
              ),
              const SizedBox(height: 18),

              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.status.isFailure && state.failure != null)
                ErrorNotice(failure: state.failure!, onRetry: cubit.load)
              else if (snap != null) ...<Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SizedBox(
                      width: mobile ? double.infinity : 240,
                      child: KpiCard(
                        label: context.tr(AppText.insightsStockValue),
                        value: Fmt.money(snap.stockValue),
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                    SizedBox(
                      width: mobile ? double.infinity : 240,
                      child: KpiCard(
                        label: context.tr(AppText.insightsDeadValue),
                        value: Fmt.money(snap.deadStockValue),
                        footnote: '${snap.deadShareBp ~/ 100}%'
                            ' · ${snap.deadStock.length}',
                        icon: Icons.hourglass_bottom,
                        tint: snap.deadShareBp > 2000 ? AppColors.danger : null,
                      ),
                    ),
                    SizedBox(
                      width: mobile ? double.infinity : 240,
                      child: KpiCard(
                        label: context.tr(AppText.insightsBusiestHour),
                        value: snap.busiestHour == null
                            ? '—'
                            : '${snap.busiestHour!.hour.toString().padLeft(2, '0')}:00',
                        footnote: snap.busiestHour == null
                            ? null
                            : '${snap.busiestHour!.salesCount}',
                        icon: Icons.schedule,
                      ),
                    ),
                    SizedBox(
                      width: mobile ? double.infinity : 240,
                      child: KpiCard(
                        label: context.tr(AppText.insightsToReorder),
                        value: '${snap.needsReorder.length}',
                        icon: Icons.add_shopping_cart,
                        tint: snap.needsReorder.isEmpty
                            ? null
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<int>>[
                    ButtonSegment<int>(
                      value: 0,
                      label: Text(context.tr(AppText.insightsDead)),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text(context.tr(AppText.insightsEarners)),
                    ),
                    ButtonSegment<int>(
                      value: 2,
                      label: Text(context.tr(AppText.insightsHours)),
                    ),
                    ButtonSegment<int>(
                      value: 3,
                      label: Text(context.tr(AppText.insightsToReorder)),
                    ),
                  ],
                  selected: <int>{state.tab},
                  onSelectionChanged: (Set<int> s) => cubit.setTab(s.first),
                ),
                const SizedBox(height: 16),

                switch (state.tab) {
                  0 => _ItemTable(
                      rows: snap.deadStock,
                      valueLabel: context.tr(AppText.insightsSittingValue),
                      value: (ItemInsight i) => Fmt.money(i.stockValue),
                      trailing: (BuildContext context, ItemInsight i) => Text(
                        i.daysSinceSold == null
                            ? context.tr(AppText.insightsNeverSold)
                            : context.tr(AppText.insightsDaysAgo,
                                params: <String, Object?>{'n': i.daysSinceSold}),
                        style: TextStyle(
                          color: i.daysSinceSold == null
                              ? AppColors.danger
                              : Theme.of(context).surfaces.muted,
                        ),
                      ),
                    ),
                  1 => _ItemTable(
                      rows: snap.bestMargins,
                      valueLabel: context.tr(AppText.insightsProfit30d),
                      value: (ItemInsight i) => Fmt.money(i.profit30d),
                      trailing: (BuildContext context, ItemInsight i) =>
                          Text('${i.marginBp ~/ 100}%'),
                    ),
                  2 => _Hours(snapshot: snap),
                  _ => _ItemTable(
                      rows: snap.needsReorder,
                      valueLabel: context.tr(AppText.insightsCover),
                      value: (ItemInsight i) => i.daysOfCover == null
                          ? '—'
                          : context.tr(AppText.insightsDays,
                              params: <String, Object?>{'n': i.daysOfCover}),
                      trailing: (BuildContext context, ItemInsight i) => Text(
                        '${Fmt.qtyMilli(i.stockMilli)}'
                        ' / ${Fmt.qtyMilli(i.reorderLevelMilli)}',
                      ),
                    ),
                },
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ItemTable extends StatelessWidget {
  const _ItemTable({
    required this.rows,
    required this.valueLabel,
    required this.value,
    required this.trailing,
  });

  final List<ItemInsight> rows;
  final String valueLabel;
  final String Function(ItemInsight item) value;
  final Widget Function(BuildContext context, ItemInsight item) trailing;

  @override
  Widget build(BuildContext context) {
    return AdminTable<ItemInsight>(
      rows: rows,
      empty: EmptyState(
        icon: Icons.insights_outlined,
        message: context.tr(AppText.insightsNothing),
      ),
      mobileCard: (BuildContext context, ItemInsight row) => AdminRecordCard(
        title: row.name,
        subtitle: row.categoryName,
        trailing: Text(value(row)),
        details: <Widget>[
          RecordDetail(
            label: context.tr(AppText.stock),
            value: Fmt.qtyMilli(row.stockMilli),
          ),
        ],
      ),
      columns: <AdminColumn<ItemInsight>>[
        AdminColumn<ItemInsight>(
          label: context.tr(AppText.name),
          flex: 5,
          cell: (BuildContext context, ItemInsight row) => Text(row.name),
        ),
        AdminColumn<ItemInsight>(
          label: context.tr(AppText.category),
          flex: 3,
          hideBelow: 900,
          cell: (BuildContext context, ItemInsight row) =>
              Text(row.categoryName ?? '—'),
        ),
        AdminColumn<ItemInsight>(
          label: context.tr(AppText.stock),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, ItemInsight row) =>
              Text(Fmt.qtyMilli(row.stockMilli)),
        ),
        AdminColumn<ItemInsight>(
          label: valueLabel,
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, ItemInsight row) => Text(
            value(row),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        AdminColumn<ItemInsight>(
          label: '',
          flex: 3,
          alignEnd: true,
          cell: trailing,
        ),
      ],
    );
  }
}

/// The trading day as a row of bars, drawn from the numbers rather than by a
/// charting library — one screen does not justify the dependency.
class _Hours extends StatelessWidget {
  const _Hours({required this.snapshot});

  final InsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (snapshot.hours.isEmpty) {
      return EmptyState(
        icon: Icons.schedule,
        message: context.tr(AppText.insightsNothing),
      );
    }

    final int peak = snapshot.hours
        .map((HourOfDay h) => h.total.minor)
        .reduce((int a, int b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.surfaces.hairline),
      ),
      child: Column(
        children: <Widget>[
          for (final HourOfDay h in snapshot.hours)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${h.hour.toString().padLeft(2, '0')}:00',
                      style: theme.textTheme.bodySmall?.merge(theme.tabular),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: peak == 0 ? 0 : h.total.minor / peak,
                        minHeight: 10,
                        backgroundColor: theme.surfaces.hairline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: Text(
                      Fmt.money(h.total),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.merge(theme.tabular),
                    ),
                  ),
                  SizedBox(
                    width: 54,
                    child: Text(
                      '${h.salesCount}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.surfaces.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class InsightsRoutes {
  const InsightsRoutes._();

  static const String path = '/insights';

  static Widget standalone() => BlocProvider<InsightsCubit>(
        create: (_) => InsightsCubit(sl<InsightsRepository>())..load(),
        child: const InsightsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
