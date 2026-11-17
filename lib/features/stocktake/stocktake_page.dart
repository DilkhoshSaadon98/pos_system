import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/money/money.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/modals.dart';
import '../../core/widgets/panels.dart';
import '../auth/presentation/cubit/auth_cubit.dart';
import '../catalog/domain/entities/catalog_entities.dart';
import '../catalog/domain/repositories/catalog_repository.dart';
import 'stocktake_feature.dart';

class StocktakeState {
  const StocktakeState({
    this.status = AppStatus.initial,
    this.sessions = const <StockCount>[],
    this.categories = const <Category>[],
    this.open,
    this.lines = const <StockCountLine>[],
    this.onlyUncounted = false,
    this.search = '',
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<StockCount> sessions;
  final List<Category> categories;

  /// The sheet being filled in, if any.
  final StockCount? open;
  final List<StockCountLine> lines;

  final bool onlyUncounted;
  final String search;
  final bool busy;
  final Failure? failure;

  List<StockCountLine> get visibleLines {
    Iterable<StockCountLine> rows = lines;
    if (onlyUncounted) {
      rows = rows.where((StockCountLine l) => !l.isCounted);
    }
    final String text = search.trim().toLowerCase();
    if (text.isNotEmpty) {
      rows = rows.where((StockCountLine l) =>
          l.itemName.toLowerCase().contains(text) ||
          (l.sku ?? '').toLowerCase().contains(text));
    }
    return rows.toList(growable: false);
  }

  /// What the count has found so far — the number a manager watches while it
  /// is still being done.
  Money get runningVariance => Money(lines.fold(
        0,
        (int sum, StockCountLine l) => sum + l.varianceValue.minor,
      ));

  int get countedCount => lines.where((StockCountLine l) => l.isCounted).length;

  StocktakeState copyWith({
    AppStatus? status,
    List<StockCount>? sessions,
    List<Category>? categories,
    StockCount? open,
    bool clearOpen = false,
    List<StockCountLine>? lines,
    bool? onlyUncounted,
    String? search,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      StocktakeState(
        status: status ?? this.status,
        sessions: sessions ?? this.sessions,
        categories: categories ?? this.categories,
        open: clearOpen ? null : (open ?? this.open),
        lines: lines ?? this.lines,
        onlyUncounted: onlyUncounted ?? this.onlyUncounted,
        search: search ?? this.search,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class StocktakeCubit extends Cubit<StocktakeState> {
  StocktakeCubit({
    required StocktakeRepository stocktake,
    required CatalogRepository catalog,
    int? userId,
  })  : _stocktake = stocktake,
        _catalog = catalog,
        _userId = userId,
        super(const StocktakeState());

  final StocktakeRepository _stocktake;
  final CatalogRepository _catalog;
  final int? _userId;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<List<StockCount>> sessions = await _stocktake.sessions();
    final Result<List<Category>> categories = await _catalog.categories();
    if (isClosed) return;

    final Failure? failure = sessions.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    final List<StockCount> all = sessions.valueOr(const <StockCount>[]);
    emit(state.copyWith(
      status: AppStatus.ready,
      sessions: all,
      categories: categories.valueOr(const <Category>[]),
      clearFailure: true,
    ));

    // A sheet left open is the thing the person opening this screen almost
    // certainly came back for.
    final StockCount? open =
        all.where((StockCount s) => s.isOpen).cast<StockCount?>().firstWhere(
              (StockCount? s) => true,
              orElse: () => null,
            );
    if (open != null) await openSheet(open);
  }

  Future<void> openSheet(StockCount count) async {
    emit(state.copyWith(open: count, busy: true, clearFailure: true));
    final Result<List<StockCountLine>> lines = await _stocktake.lines(count.id);
    if (isClosed) return;
    emit(state.copyWith(
      busy: false,
      lines: lines.valueOr(const <StockCountLine>[]),
      failure: lines.failureOrNull,
    ));
  }

  void closeSheet() =>
      emit(state.copyWith(clearOpen: true, lines: const <StockCountLine>[]));

  void setOnlyUncounted(bool v) => emit(state.copyWith(onlyUncounted: v));

  void setSearch(String text) => emit(state.copyWith(search: text));

  Future<bool> start({int? categoryId, String? note}) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _stocktake.start(
      categoryId: categoryId,
      userId: _userId,
      note: note,
    );
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    if (failure != null) return false;

    await load();
    return true;
  }

  /// Records one count without reloading the sheet — a person counting a shelf
  /// types a number every few seconds, and a reload between each one would
  /// make the screen unusable.
  Future<void> setCounted(StockCountLine line, int? countedMilli) async {
    final Result<dynamic> result = await _stocktake.setCounted(
      lineId: line.id,
      countedQtyMilli: countedMilli,
      userId: _userId,
    );
    if (isClosed) return;

    if (result.failed) {
      emit(state.copyWith(failure: result.failureOrNull));
      return;
    }

    emit(state.copyWith(
      lines: <StockCountLine>[
        for (final StockCountLine l in state.lines)
          if (l.id == line.id)
            StockCountLine(
              id: l.id,
              itemId: l.itemId,
              itemName: l.itemName,
              sku: l.sku,
              unitName: l.unitName,
              systemQtyMilli: l.systemQtyMilli,
              countedQtyMilli: countedMilli,
              unitCost: l.unitCost,
              note: l.note,
            )
          else
            l,
      ],
    ));
  }

  Future<Money?> post() async {
    final StockCount? sheet = state.open;
    if (sheet == null) return null;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<Money> result = await _stocktake.post(sheet.id, userId: _userId);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    if (failure != null) return null;

    closeSheet();
    await load();
    return result.valueOrNull;
  }

  Future<void> cancel() async {
    final StockCount? sheet = state.open;
    if (sheet == null) return;
    await _stocktake.cancel(sheet.id, userId: _userId);
    if (isClosed) return;
    closeSheet();
    await load();
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

/// Counting the shop.
class StocktakePage extends StatefulWidget {
  const StocktakePage({super.key});

  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<StocktakeCubit, StocktakeState>(
      listenWhen: (StocktakeState a, StocktakeState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, StocktakeState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<StocktakeCubit>().clearFailure();
      },
      builder: (BuildContext context, StocktakeState state) {
        final StocktakeCubit cubit = context.read<StocktakeCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.stocktakeTitle),
                subtitle: state.open?.countNo,
                actions: <Widget>[
                  if (state.open == null)
                    FilledButton.icon(
                      onPressed:
                          state.busy ? null : () => _start(context, cubit),
                      icon: const Icon(Icons.playlist_add_check, size: 18),
                      label: Text(context.tr(AppText.stocktakeStart)),
                    )
                  else ...<Widget>[
                    TextButton.icon(
                      onPressed: state.busy
                          ? null
                          : () async {
                              final bool ok = await confirm(
                                context,
                                title: context.tr(AppText.stocktakeCancel),
                                message:
                                    context.tr(AppText.stocktakeCancelWarning),
                              );
                              if (ok) await cubit.cancel();
                            },
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(context.tr(AppText.stocktakeCancel)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: state.busy || state.countedCount == 0
                          ? null
                          : () => _post(context, cubit, state),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(context.tr(AppText.stocktakePost)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),

              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.open != null) ...<Widget>[
                _SheetSummary(state: state),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        controller: _search,
                        label: context.tr(AppText.search),
                        prefixIcon: Icons.search,
                        onChanged: cubit.setSearch,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: Text(context.tr(AppText.stocktakeUncountedOnly)),
                      selected: state.onlyUncounted,
                      onSelected: cubit.setOnlyUncounted,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SheetTable(state: state, cubit: cubit),
              ] else
                _History(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }

  Future<void> _start(BuildContext context, StocktakeCubit cubit) async {
    int? categoryId;
    await showAppModal<void>(
      context,
      title: context.tr(AppText.stocktakeStart),
      subtitle: context.tr(AppText.stocktakeStartHint),
      width: 480,
      builder: (BuildContext modalContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppDropdown<int>(
              label: context.tr(AppText.category),
              helper: context.tr(AppText.stocktakeScopeHint),
              value: categoryId,
              items: <int>[0, ...cubit.state.categories.map((Category c) => c.id)],
              itemLabel: (int id) => id == 0
                  ? context.tr(AppText.all)
                  : cubit.state.categories
                      .firstWhere((Category c) => c.id == id)
                      .name,
              onChanged: (int? id) => setLocal(() => categoryId = id == 0 ? null : id),
            ),
            const SizedBox(height: 18),
            ModalActions(
              saveLabel: context.tr(AppText.stocktakeStart),
              onSave: () async {
                final bool ok = await cubit.start(categoryId: categoryId);
                if (ok && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _post(
    BuildContext context,
    StocktakeCubit cubit,
    StocktakeState state,
  ) async {
    final int uncounted = state.lines.length - state.countedCount;
    final bool ok = await confirm(
      context,
      destructive: false,
      icon: Icons.fact_check_outlined,
      title: context.tr(AppText.stocktakePost),
      message: context.tr(
        uncounted > 0
            ? AppText.stocktakePostPartial
            : AppText.stocktakePostConfirm,
        params: <String, Object?>{
          'n': '$uncounted',
          'value': Fmt.money(state.runningVariance),
        },
      ),
      confirmLabel: context.tr(AppText.stocktakePost),
    );
    if (!ok) return;

    final Money? found = await cubit.post();
    if (found != null && context.mounted) {
      AppSnack.success(
        context,
        context.tr(AppText.stocktakePosted,
            params: <String, Object?>{'value': Fmt.money(found)}),
      );
    }
  }
}

class _SheetSummary extends StatelessWidget {
  const _SheetSummary({required this.state});

  final StocktakeState state;

  @override
  Widget build(BuildContext context) {
    final bool mobile = Responsive.isMobile(context);
    final Money variance = state.runningVariance;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        SizedBox(
          width: mobile ? double.infinity : 230,
          child: KpiCard(
            label: context.tr(AppText.stocktakeProgress),
            value: '${state.countedCount} / ${state.lines.length}',
            icon: Icons.checklist,
          ),
        ),
        SizedBox(
          width: mobile ? double.infinity : 230,
          child: KpiCard(
            label: context.tr(AppText.stocktakeVariance),
            value: Fmt.money(variance),
            icon: variance.isNegative
                ? Icons.trending_down
                : Icons.trending_up,
            tint: variance.isZero
                ? null
                : (variance.isNegative ? AppColors.danger : AppColors.success),
            footnote: context.tr(AppText.stocktakeVarianceHint),
          ),
        ),
      ],
    );
  }
}

class _SheetTable extends StatelessWidget {
  const _SheetTable({required this.state, required this.cubit});

  final StocktakeState state;
  final StocktakeCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<StockCountLine>(
      rows: state.visibleLines,
      empty: EmptyState(
        icon: Icons.inventory_2_outlined,
        message: context.tr(AppText.nothingYet),
      ),
      rowTint: (BuildContext context, StockCountLine row) => row.isCounted &&
              row.varianceMilli != 0
          ? (row.varianceMilli < 0 ? AppColors.danger : AppColors.success)
              .withValues(alpha: 0.06)
          : null,
      mobileCard: (BuildContext context, StockCountLine row) => AdminRecordCard(
        title: row.itemName,
        subtitle: '${context.tr(AppText.stocktakeSystem)}: '
            '${Fmt.qtyMilli(row.systemQtyMilli)}',
        trailing: _CountBox(line: row, cubit: cubit),
      ),
      columns: <AdminColumn<StockCountLine>>[
        AdminColumn<StockCountLine>(
          label: context.tr(AppText.name),
          flex: 5,
          cell: (BuildContext context, StockCountLine row) => Text(row.itemName),
        ),
        AdminColumn<StockCountLine>(
          label: context.tr(AppText.stocktakeSystem),
          flex: 2,
          alignEnd: true,
          hideBelow: 800,
          cell: (BuildContext context, StockCountLine row) =>
              Text(Fmt.qtyMilli(row.systemQtyMilli)),
        ),
        AdminColumn<StockCountLine>(
          label: context.tr(AppText.stocktakeCounted),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, StockCountLine row) =>
              _CountBox(line: row, cubit: cubit),
        ),
        AdminColumn<StockCountLine>(
          label: context.tr(AppText.stocktakeVariance),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, StockCountLine row) {
            if (!row.isCounted) return const Text('—');
            final bool zero = row.varianceMilli == 0;
            return Text(
              zero
                  ? '0'
                  : '${Fmt.qtyMilli(row.varianceMilli)}  '
                      '(${Fmt.money(row.varianceValue)})',
              style: TextStyle(
                color: zero
                    ? null
                    : (row.varianceMilli < 0
                        ? AppColors.danger
                        : AppColors.success),
                fontWeight: zero ? null : FontWeight.w600,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The box a counter types into.
class _CountBox extends StatefulWidget {
  const _CountBox({required this.line, required this.cubit});

  final StockCountLine line;
  final StocktakeCubit cubit;

  @override
  State<_CountBox> createState() => _CountBoxState();
}

class _CountBoxState extends State<_CountBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.line.countedQtyMilli == null
        ? ''
        : Fmt.qtyMilli(widget.line.countedQtyMilli!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: QtyField(
        controller: _controller,
        label: '',
        onSubmitted: (Qty? q) => widget.cubit.setCounted(
          widget.line,
          q?.milli,
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.state, required this.cubit});

  final StocktakeState state;
  final StocktakeCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<StockCount>(
      rows: state.sessions,
      onRowTap: (StockCount row) => row.isOpen ? cubit.openSheet(row) : null,
      empty: EmptyState(
        icon: Icons.fact_check_outlined,
        message: context.tr(AppText.stocktakeEmpty),
      ),
      mobileCard: (BuildContext context, StockCount row) => AdminRecordCard(
        title: row.countNo,
        subtitle: Fmt.dateTime(row.startedAt),
        trailing: Text(Fmt.money(row.varianceValue)),
        onTap: () => row.isOpen ? cubit.openSheet(row) : null,
      ),
      columns: <AdminColumn<StockCount>>[
        AdminColumn<StockCount>(
          label: context.tr(AppText.stocktakeNumber),
          flex: 3,
          cell: (BuildContext context, StockCount row) => Text(row.countNo),
        ),
        AdminColumn<StockCount>(
          label: context.tr(AppText.date),
          flex: 3,
          cell: (BuildContext context, StockCount row) =>
              Text(Fmt.dateTime(row.startedAt)),
        ),
        AdminColumn<StockCount>(
          label: context.tr(AppText.category),
          flex: 3,
          hideBelow: 900,
          cell: (BuildContext context, StockCount row) =>
              Text(row.categoryName ?? context.tr(AppText.all)),
        ),
        AdminColumn<StockCount>(
          label: context.tr(AppText.stocktakeVariance),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, StockCount row) => Text(
            row.isPosted ? Fmt.money(row.varianceValue) : '—',
            style: TextStyle(
              color: row.varianceValue.isNegative ? AppColors.danger : null,
            ),
          ),
        ),
        AdminColumn<StockCount>(
          label: context.tr(AppText.status),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, StockCount row) => StatusChip(
            label: row.isOpen
                ? context.tr(AppText.stocktakeOpen)
                : (row.isPosted
                    ? context.tr(AppText.stocktakePosted0)
                    : context.tr(AppText.cancel)),
            color: row.isOpen
                ? AppColors.warning
                : (row.isPosted
                    ? AppColors.success
                    : Theme.of(context).surfaces.muted),
            compact: true,
          ),
        ),
      ],
    );
  }
}

class StocktakeRoutes {
  const StocktakeRoutes._();

  static const String path = '/stocktake';

  static Widget standalone() => Builder(
        builder: (BuildContext context) => BlocProvider<StocktakeCubit>(
          create: (_) => StocktakeCubit(
            stocktake: sl<StocktakeRepository>(),
            catalog: sl<CatalogRepository>(),
            userId: context.read<AuthCubit>().state.user?.id,
          )..load(),
          child: const StocktakePage(),
        ),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
