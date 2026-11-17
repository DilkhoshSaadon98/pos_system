import 'package:cashier_system_v2/core/classes/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/calc/purchase_calculator.dart';
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
import '../parties/domain/entities/party.dart';
import '../parties/domain/repositories/parties_repository.dart';
import '../purchases/domain/entities/purchase_document.dart';
import '../purchases/domain/repositories/purchases_repository.dart';
import 'orders_feature.dart';

class OrdersState {
  const OrdersState({
    this.status = AppStatus.initial,
    this.orders = const <PurchaseOrder>[],
    this.suppliers = const <Party>[],
    this.suggestions = const <Map<String, Object?>>[],
    this.selected,
    this.lines = const <OrderLine>[],
    this.onlyOpen = true,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<PurchaseOrder> orders;
  final List<Party> suppliers;

  /// What is below its reorder level, with who last supplied it.
  final List<Map<String, Object?>> suggestions;

  final PurchaseOrder? selected;
  final List<OrderLine> lines;
  final bool onlyOpen;
  final bool busy;
  final Failure? failure;

  OrdersState copyWith({
    AppStatus? status,
    List<PurchaseOrder>? orders,
    List<Party>? suppliers,
    List<Map<String, Object?>>? suggestions,
    PurchaseOrder? selected,
    bool clearSelected = false,
    List<OrderLine>? lines,
    bool? onlyOpen,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      OrdersState(
        status: status ?? this.status,
        orders: orders ?? this.orders,
        suppliers: suppliers ?? this.suppliers,
        suggestions: suggestions ?? this.suggestions,
        selected: clearSelected ? null : (selected ?? this.selected),
        lines: lines ?? this.lines,
        onlyOpen: onlyOpen ?? this.onlyOpen,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit({
    required OrdersRepository orders,
    required PartiesRepository parties,
    required PurchasesRepository purchases,
    int? userId,
  })  : _orders = orders,
        _parties = parties,
        _purchases = purchases,
        _userId = userId,
        super(const OrdersState());

  final OrdersRepository _orders;
  final PartiesRepository _parties;
  final PurchasesRepository _purchases;
  final int? _userId;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<List<PurchaseOrder>> orders = await _orders.search(
      from: DateTime.now().subtract(const Duration(days: 180)),
      to: DateTime.now(),
      onlyOpen: state.onlyOpen,
    );
    final Result<List<Party>> suppliers =
        await _parties.search(kind: PartyKind.supplier);
    final Result<List<Map<String, Object?>>> suggestions =
        await _orders.reorderSuggestions();
    if (isClosed) return;

    final Failure? failure = orders.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    emit(state.copyWith(
      status: AppStatus.ready,
      orders: orders.valueOrNull,
      suppliers: suppliers.valueOr(const <Party>[]),
      suggestions: suggestions.valueOr(const <Map<String, Object?>>[]),
      clearFailure: true,
    ));
  }

  Future<void> toggleOpenOnly(bool value) {
    emit(state.copyWith(onlyOpen: value));
    return load();
  }

  Future<void> open(PurchaseOrder order) async {
    emit(state.copyWith(selected: order, busy: true));
    final Result<List<OrderLine>> lines = await _orders.lines(order.id);
    if (isClosed) return;
    emit(state.copyWith(
      busy: false,
      lines: lines.valueOr(const <OrderLine>[]),
      failure: lines.failureOrNull,
    ));
  }

  void closeDetail() =>
      emit(state.copyWith(clearSelected: true, lines: const <OrderLine>[]));

  Future<bool> save({
    int? id,
    required int partyId,
    required List<OrderLineInput> lines,
    DateTime? expectedAt,
    String? note,
  }) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _orders.save(
      id: id,
      partyId: partyId,
      lines: lines,
      expectedAt: expectedAt,
      userId: _userId,
      note: note,
      status: OrderStatus.sent,
    );
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    if (failure != null) return false;

    await load();
    return true;
  }

  Future<bool> cancel(PurchaseOrder order) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result =
        await _orders.setStatus(order.id, OrderStatus.cancelled, userId: _userId);
    if (isClosed) return false;
    emit(state.copyWith(busy: false, failure: result.failureOrNull));
    await load();
    return result.succeeded;
  }

  /// Turns what is still outstanding into a purchase invoice.
  ///
  /// The invoice is posted by the ordinary purchase path — same landed costs,
  /// same journal, same stock movements — and the order is updated inside that
  /// same transaction, so the two can never disagree about what arrived.
  Future<PostedPurchase?> receive(PurchaseOrder order) async {
    final List<OrderLine> outstanding =
        state.lines.where((OrderLine l) => l.outstandingMilli > 0).toList();
    if (outstanding.isEmpty) return null;

    emit(state.copyWith(busy: true, clearFailure: true));

    final PurchaseTotals totals = const PurchaseCalculator().compute(
      lines: <PurchaseLineInput>[
        for (final OrderLine l in outstanding)
          PurchaseLineInput(
            itemId: l.itemId,
            qtyMilli: l.outstandingMilli,
            unitCostMinor: l.unitCost.minor,
            itemUnitId: l.itemUnitId,
            unitName: l.unitName,
            factorMilli: l.factorMilli,
          ),
      ],
    );

    final Result<PostedPurchase> posted = await _purchases.postPurchase(
      totals: totals,
      partyId: order.partyId,
      userId: _userId,
      note: 'Order ${order.orderNo}',
      orderId: order.id,
    );
    if (isClosed) return null;

    final Failure? failure = posted.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    if (failure != null) return null;

    await load();
    return posted.valueOrNull;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

/// What has been asked of suppliers, and what is still owed.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrdersCubit, OrdersState>(
      listenWhen: (OrdersState a, OrdersState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, OrdersState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<OrdersCubit>().clearFailure();
      },
      builder: (BuildContext context, OrdersState state) {
        final OrdersCubit cubit = context.read<OrdersCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.ordersTitle),
                subtitle: '${state.orders.length}',
                actions: <Widget>[
                  FilterChip(
                    label: Text(context.tr(AppText.ordersOpenOnly)),
                    selected: state.onlyOpen,
                    onSelected: cubit.toggleOpenOnly,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: state.busy
                        ? null
                        : () => _edit(context, cubit, null),
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: Text(context.tr(AppText.ordersNew)),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (state.suggestions.isNotEmpty) ...<Widget>[
                _ReorderCard(state: state, cubit: cubit),
                const SizedBox(height: 18),
              ],

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
                AdminTable<PurchaseOrder>(
                  rows: state.orders,
                  onRowTap: (PurchaseOrder row) => _detail(context, cubit, row),
                  empty: EmptyState(
                    icon: Icons.assignment_outlined,
                    message: context.tr(AppText.nothingYet),
                  ),
                  mobileCard: (BuildContext context, PurchaseOrder row) =>
                      AdminRecordCard(
                    title: row.orderNo,
                    subtitle: row.partyName,
                    trailing: Text(Fmt.money(row.total)),
                    onTap: () => _detail(context, cubit, row),
                    details: <Widget>[
                      RecordDetail(
                        label: context.tr(AppText.ordersReceived),
                        value: '${row.receivedBp ~/ 100}%',
                      ),
                    ],
                  ),
                  columns: <AdminColumn<PurchaseOrder>>[
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.ordersNumber),
                      flex: 3,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          Text(row.orderNo),
                    ),
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.supplier),
                      flex: 4,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          Text(row.partyName),
                    ),
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.date),
                      flex: 3,
                      hideBelow: 900,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          Text(Fmt.date(row.orderedAt)),
                    ),
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.ordersReceived),
                      flex: 3,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          _Progress(bp: row.receivedBp),
                    ),
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.total),
                      flex: 3,
                      alignEnd: true,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          Text(Fmt.money(row.total)),
                    ),
                    AdminColumn<PurchaseOrder>(
                      label: context.tr(AppText.status),
                      flex: 2,
                      alignEnd: true,
                      cell: (BuildContext context, PurchaseOrder row) =>
                          StatusChip(
                        label: _statusLabel(context, row.status),
                        color: switch (row.status) {
                          OrderStatus.received => AppColors.success,
                          OrderStatus.partial => AppColors.warning,
                          OrderStatus.cancelled => AppColors.danger,
                          _ => Theme.of(context).surfaces.muted,
                        },
                        compact: true,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  static String _statusLabel(BuildContext context, OrderStatus s) =>
      switch (s) {
        OrderStatus.draft => context.tr(AppText.ordersDraft),
        OrderStatus.sent => context.tr(AppText.ordersSent),
        OrderStatus.partial => context.tr(AppText.ordersPartial),
        OrderStatus.received => context.tr(AppText.ordersReceivedFully),
        OrderStatus.cancelled => context.tr(AppText.cancel),
      };

  static Future<void> _edit(
    BuildContext context,
    OrdersCubit cubit,
    PurchaseOrder? order, {
    List<OrderLineInput> seed = const <OrderLineInput>[],
    int? seedPartyId,
  }) =>
      showAppModal<void>(
        context,
        title: context.tr(AppText.ordersNew),
        width: 760,
        builder: (BuildContext modalContext) => _OrderForm(
          cubit: cubit,
          seed: seed,
          seedPartyId: seedPartyId,
        ),
      );

  static Future<void> _detail(
    BuildContext context,
    OrdersCubit cubit,
    PurchaseOrder order,
  ) async {
    await cubit.open(order);
    if (!context.mounted) return;
    await showAppModal<void>(
      context,
      title: order.orderNo,
      subtitle: order.partyName,
      width: 720,
      builder: (BuildContext modalContext) =>
          _OrderDetail(cubit: cubit, order: order),
    );
    cubit.closeDetail();
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.bp});

  final int bp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (bp / 10000).clamp(0, 1),
              minHeight: 6,
              backgroundColor: theme.surfaces.hairline,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${bp ~/ 100}%', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// What is below its level, and who last sold it to the shop.
class _ReorderCard extends StatelessWidget {
  const _ReorderCard({required this.state, required this.cubit});

  final OrdersState state;
  final OrdersCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Map<String, Object?>> rows = state.suggestions.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.inventory_2_outlined,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(AppText.ordersReorderTitle),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('${state.suggestions.length}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Map<String, Object?> r in rows)
                Chip(
                  label: Text(
                    '${r['item_name']}  ·  '
                    '${Fmt.qtyMilli(r['stock_qty_milli'] as int? ?? 0)}'
                    '${r['last_party_name'] == null ? '' : '  ·  ${r['last_party_name']}'}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: () => _orderTheseFrom(context),
              icon: const Icon(Icons.playlist_add, size: 18),
              label: Text(context.tr(AppText.ordersFromSuggestions)),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds one order per supplier from the suggestion list — a shop orders
  /// from a supplier, not from a report.
  void _orderTheseFrom(BuildContext context) {
    final Map<int, List<OrderLineInput>> bySupplier =
        <int, List<OrderLineInput>>{};

    for (final Map<String, Object?> r in state.suggestions) {
      final int? partyId = r['last_party_id'] as int?;
      if (partyId == null) continue;
      final int level = r['reorder_level_milli'] as int? ?? 0;
      final int have = r['stock_qty_milli'] as int? ?? 0;
      // Order back up to the level, plus the same again as cover, which is the
      // rule of thumb a shopkeeper uses when nothing better is known.
      final int need = ((level - have) + level).clamp(1000, 1 << 40);

      bySupplier.putIfAbsent(partyId, () => <OrderLineInput>[]).add(
            OrderLineInput(
              itemId: r['item_id'] as int,
              qtyMilli: need,
              unitCostMinor: r['last_cost_minor'] as int? ??
                  (r['avg_cost_minor'] as int? ?? 0),
            ),
          );
    }

    if (bySupplier.isEmpty) {
      AppSnack.info(context, context.tr(AppText.ordersNoSupplierYet));
      return;
    }

    final MapEntry<int, List<OrderLineInput>> first = bySupplier.entries.first;
    OrdersPage._edit(
      context,
      cubit,
      null,
      seed: first.value,
      seedPartyId: first.key,
    );
  }
}

class _OrderForm extends StatefulWidget {
  const _OrderForm({
    required this.cubit,
    this.seed = const <OrderLineInput>[],
    this.seedPartyId,
  });

  final OrdersCubit cubit;
  final List<OrderLineInput> seed;
  final int? seedPartyId;

  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
  late int? _partyId = widget.seedPartyId;
  late final List<OrderLineInput> _lines = <OrderLineInput>[...widget.seed];

  /// Item names for the rows on screen. The order itself stores ids — a name
  /// that changes later should not change what was ordered — so the labels are
  /// kept here, beside the form that shows them.
  final Map<int, String> _names = <int, String>{};
  final TextEditingController _search = TextEditingController();
  final TextEditingController _note = TextEditingController();
  List<Item> _results = const <Item>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _find('');
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _find(String text) async {
    final Result<List<Item>> items =
        await sl<CatalogRepository>().searchItems(text: text, limit: 30);
    if (!mounted) return;
    setState(() => _results = items.valueOr(const <Item>[]));
  }

  int get _totalMinor =>
      _lines.fold(0, (int sum, OrderLineInput l) => sum + l.totalMinor);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppDropdown<int>(
          label: context.tr(AppText.supplier),
          value: _partyId,
          items: widget.cubit.state.suppliers.map((Party p) => p.id).toList(),
          itemLabel: (int id) => widget.cubit.state.suppliers
              .firstWhere((Party p) => p.id == id)
              .name,
          onChanged: (int? id) => setState(() => _partyId = id),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _search,
          label: context.tr(AppText.search),
          prefixIcon: Icons.search,
          onChanged: _find,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Item item in _results.take(12))
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(item.name),
                onPressed: () => setState(() {
                  _names[item.id] = item.name;
                  _lines.add(OrderLineInput(
                    itemId: item.id,
                    qtyMilli: 1000,
                    unitCostMinor: item.lastCost.minor > 0
                        ? item.lastCost.minor
                        : item.avgCost.minor,
                    unitName: item.baseUnitName,
                  ));
                }),
              ),
          ],
        ),
        const Divider(height: 26),

        if (_lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              context.tr(AppText.ordersPickItems),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.surfaces.muted),
            ),
          )
        else
          for (int i = 0; i < _lines.length; i++)
            _LineRow(
              line: _lines[i],
              name: _names[_lines[i].itemId] ?? '#${_lines[i].itemId}',
              onChanged: (OrderLineInput l) => setState(() => _lines[i] = l),
              onRemove: () => setState(() => _lines.removeAt(i)),
            ),

        const SizedBox(height: 10),
        TotalRow(
          label: context.tr(AppText.total),
          value: Fmt.moneyMinor(_totalMinor),
          emphasis: true,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: context.tr(AppText.note),
          maxLines: 2,
        ),
        const SizedBox(height: 18),
        ModalActions(
          busy: _busy,
          saveLabel: context.tr(AppText.ordersSend),
          onSave: _partyId == null || _lines.isEmpty ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final bool ok = await widget.cubit.save(
      partyId: _partyId!,
      lines: _lines,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.name,
    required this.onChanged,
    required this.onRemove,
  });

  final OrderLineInput line;
  final String name;
  final ValueChanged<OrderLineInput> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: line.qtyMilli <= 1000
                ? null
                : () => onChanged(OrderLineInput(
                      itemId: line.itemId,
                      qtyMilli: line.qtyMilli - 1000,
                      unitCostMinor: line.unitCostMinor,
                      itemUnitId: line.itemUnitId,
                      unitName: line.unitName,
                      factorMilli: line.factorMilli,
                    )),
          ),
          Text(Fmt.qtyMilli(line.qtyMilli)),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => onChanged(OrderLineInput(
              itemId: line.itemId,
              qtyMilli: line.qtyMilli + 1000,
              unitCostMinor: line.unitCostMinor,
              itemUnitId: line.itemUnitId,
              unitName: line.unitName,
              factorMilli: line.factorMilli,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              Fmt.moneyMinor(line.totalMinor),
              textAlign: TextAlign.end,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 17),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.cubit, required this.order});

  final OrdersCubit cubit;
  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, OrdersState>(
      builder: (BuildContext context, OrdersState state) {
        final bool anythingLeft =
            state.lines.any((OrderLine l) => l.outstandingMilli > 0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final OrderLine l in state.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(flex: 5, child: Text(l.itemName)),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${Fmt.qtyMilli(l.receivedQtyMilli)}'
                        ' / ${Fmt.qtyMilli(l.qtyMilli)}',
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        Fmt.money(Money(
                            (l.unitCost.minor * l.qtyMilli) ~/ 1000)),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    if (l.isComplete)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: 10),
                        child: Icon(Icons.check_circle_outline,
                            size: 18, color: AppColors.success),
                      )
                    else
                      const SizedBox(width: 28),
                  ],
                ),
              ),
            const Divider(height: 26),
            TotalRow(
              label: context.tr(AppText.total),
              value: Fmt.money(order.total),
              emphasis: true,
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                if (order.isOpen)
                  TextButton.icon(
                    onPressed: state.busy
                        ? null
                        : () async {
                            final bool ok = await confirm(
                              context,
                              title: context.tr(AppText.ordersCancel),
                              message: context.tr(AppText.ordersCancelWarning),
                            );
                            if (!ok || !context.mounted) return;
                            await cubit.cancel(order);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.block, size: 18),
                    label: Text(context.tr(AppText.ordersCancel)),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: !anythingLeft || state.busy
                      ? null
                      : () async {
                          final PostedPurchase? posted =
                              await cubit.receive(order);
                          if (!context.mounted) return;
                          if (posted != null) {
                            AppSnack.success(
                              context,
                              context.tr(
                                AppText.ordersReceivedInto,
                                params: <String, Object?>{
                                  'no': posted.invoiceNo,
                                },
                              ),
                            );
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.inventory, size: 18),
                  label: Text(context.tr(AppText.ordersReceive)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class OrdersRoutes {
  const OrdersRoutes._();

  static const String path = '/orders';

  static Widget standalone() => Builder(
        builder: (BuildContext context) => BlocProvider<OrdersCubit>(
          create: (_) => OrdersCubit(
            orders: sl<OrdersRepository>(),
            parties: sl<PartiesRepository>(),
            purchases: sl<PurchasesRepository>(),
            userId: context.read<AuthCubit>().state.user?.id,
          )..load(),
          child: const OrdersPage(),
        ),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
