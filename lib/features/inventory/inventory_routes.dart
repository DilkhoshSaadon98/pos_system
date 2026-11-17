import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/classes/enums.dart';
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
import 'inventory_injection.dart';

class InventoryState {
  InventoryState({
    this.status = AppStatus.initial,
    this.moves = const <StockMove>[],
    this.totals = InventoryTotals.empty,
    DateTime? from,
    DateTime? to,
    this.kind,
    this.search = '',
    this.failure,
  })  : from = from ?? DateTime.now().subtract(const Duration(days: 30)),
        to = to ?? DateTime.now();

  final AppStatus status;
  final List<StockMove> moves;
  final InventoryTotals totals;
  final DateTime from;
  final DateTime to;
  final StockMoveKind? kind;
  final String search;
  final Failure? failure;

  InventoryState copyWith({
    AppStatus? status,
    List<StockMove>? moves,
    InventoryTotals? totals,
    DateTime? from,
    DateTime? to,
    StockMoveKind? kind,
    bool clearKind = false,
    String? search,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      InventoryState(
        status: status ?? this.status,
        moves: moves ?? this.moves,
        totals: totals ?? this.totals,
        from: from ?? this.from,
        to: to ?? this.to,
        kind: clearKind ? null : (kind ?? this.kind),
        search: search ?? this.search,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Every movement of every item, in one list.
///
/// This screen is the answer to "where did those twelve go?", and it is
/// deliberately read-only: nothing may write a stock movement except the
/// service that also keeps the cached quantity and the ledger in step.
class InventoryCubit extends Cubit<InventoryState> {
  InventoryCubit(this._repository) : super(InventoryState());

  final InventoryRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));

    final Result<List<StockMove>> moves = await _repository.movements(
      from: state.from,
      to: state.to,
      kind: state.kind,
      search: state.search,
    );
    final Result<InventoryTotals> totals = await _repository.totals();
    if (isClosed) return;

    final Failure? failure = moves.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            moves: moves.valueOrNull,
            totals: totals.valueOr(InventoryTotals.empty),
            clearFailure: true,
          ));
  }

  void setRange(DateTime from, DateTime to) {
    emit(state.copyWith(from: from, to: to));
    load();
  }

  void filterKind(StockMoveKind? kind) {
    emit(kind == null
        ? state.copyWith(clearKind: true)
        : state.copyWith(kind: kind));
    load();
  }

  void search(String text) {
    emit(state.copyWith(search: text));
    load();
  }
}

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryCubit, InventoryState>(
      builder: (BuildContext context, InventoryState state) {
        final InventoryCubit cubit = context.read<InventoryCubit>();

        return ListView(
          padding: EdgeInsets.fromLTRB(
            Responsive.isMobile(context) ? 14 : 24,
            20,
            Responsive.isMobile(context) ? 14 : 24,
            40,
          ),
          children: <Widget>[
            SectionHeader(
              title: context.tr(AppText.stockMovements),
              subtitle:
                  '${Fmt.date(state.from.toIso8601String())}  →  ${Fmt.date(state.to.toIso8601String())}',
              actions: <Widget>[
                OutlinedButton.icon(
                  onPressed: () async {
                    final DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(DateTime.now().year - 5),
                      lastDate: DateTime(DateTime.now().year + 1),
                      initialDateRange:
                          DateTimeRange(start: state.from, end: state.to),
                    );
                    if (picked != null) {
                      cubit.setRange(picked.start, picked.end);
                    }
                  },
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(context.tr(AppText.period)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth < 560 ? 2 : 4;
                const double gap = 12;
                final double width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    SizedBox(
                      width: width,
                      child: KpiCard(
                        icon: Icons.inventory_2_outlined,
                        label: context.tr(AppText.itemsStockValue),
                        value: Fmt.money(state.totals.stockValue),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: KpiCard(
                        icon: Icons.category_outlined,
                        label: context.tr(AppText.items),
                        value: '${state.totals.itemCount}',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: KpiCard(
                        icon: Icons.warning_amber_rounded,
                        label: context.tr(AppText.itemsFilterLow),
                        value: '${state.totals.lowCount}',
                        tint: AppColors.warning,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: KpiCard(
                        icon: Icons.production_quantity_limits,
                        label: context.tr(AppText.itemsFilterOut),
                        value: '${state.totals.outCount}',
                        tint: AppColors.danger,
                        footnote: state.totals.negativeCount == 0
                            ? null
                            : '${state.totals.negativeCount} < 0',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: <Widget>[
                    TextField(
                      onChanged: cubit.search,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: context.tr(AppText.search),
                        prefixIcon: const Icon(Icons.search, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: Text(context.tr(AppText.all)),
                              selected: state.kind == null,
                              onSelected: (_) => cubit.filterKind(null),
                            ),
                          ),
                          for (final StockMoveKind k in StockMoveKind.values)
                            Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(context.tr(k.labelKey)),
                                selected: state.kind == k,
                                onSelected: (_) => cubit.filterKind(k),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.status.isBusyFirstTime)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.status.isFailure && state.failure != null)
              ErrorNotice(failure: state.failure!, onRetry: cubit.load)
            else
              AdminTable<StockMove>(
                rows: state.moves,
                empty: EmptyState(
                  icon: Icons.warehouse_outlined,
                  message: context.tr(AppText.nothingYet),
                ),
                columns: <AdminColumn<StockMove>>[
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.item),
                    flex: 4,
                    cell: (BuildContext context, StockMove row) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          row.itemName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          Fmt.dateTime(row.movedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.type),
                    flex: 2,
                    cell: (BuildContext context, StockMove row) => StatusChip(
                      compact: true,
                      label: context.tr(row.kind.labelKey),
                      color: row.isIn ? AppColors.ok : AppColors.info,
                    ),
                  ),
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.note),
                    flex: 3,
                    hideBelow: 1100,
                    cell: (BuildContext context, StockMove row) => Text(
                      row.note ?? '—',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.qty),
                    flex: 2,
                    alignEnd: true,
                    cell: (BuildContext context, StockMove row) => Text(
                      '${row.isIn ? '+' : ''}${Fmt.qtyMilli(row.qtyMilli)} ${row.unitName}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: row.isIn ? AppColors.ok : AppColors.danger,
                          )
                          .merge(Theme.of(context).tabular),
                    ),
                  ),
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.stockBalanceAfter),
                    flex: 2,
                    alignEnd: true,
                    hideBelow: 900,
                    cell: (BuildContext context, StockMove row) => Text(
                      Fmt.qtyMilli(row.balanceAfterMilli),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.merge(Theme.of(context).tabular),
                    ),
                  ),
                  AdminColumn<StockMove>(
                    label: context.tr(AppText.cost),
                    flex: 2,
                    alignEnd: true,
                    hideBelow: 1300,
                    cell: (BuildContext context, StockMove row) => Text(
                      Fmt.money(row.unitCost),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                mobileCard: (BuildContext context, StockMove row) =>
                    AdminRecordCard(
                  title: row.itemName,
                  subtitle: Fmt.dateTime(row.movedAt),
                  trailing: StatusChip(
                    compact: true,
                    label:
                        '${row.isIn ? '+' : ''}${Fmt.qtyMilli(row.qtyMilli)}',
                    color: row.isIn ? AppColors.ok : AppColors.danger,
                  ),
                  details: <Widget>[
                    RecordDetail(
                      label: context.tr(AppText.type),
                      value: context.tr(row.kind.labelKey),
                    ),
                    RecordDetail(
                      label: context.tr(AppText.stockBalanceAfter),
                      value: Fmt.qtyMilli(row.balanceAfterMilli),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class InventoryRoutes {
  const InventoryRoutes._();

  static const String path = '/stock';

  static Widget standalone() => BlocProvider<InventoryCubit>(
        create: (_) => InventoryCubit(sl<InventoryRepository>())..load(),
        child: const InventoryPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
