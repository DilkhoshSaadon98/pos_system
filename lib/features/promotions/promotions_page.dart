import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/calc/promotions.dart';
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
import 'promotions_feature.dart';

class PromotionsState {
  const PromotionsState({
    this.status = AppStatus.initial,
    this.rows = const <Map<String, Object?>>[],
    this.performance = const <Map<String, Object?>>[],
    this.loyalty = const <Map<String, Object?>>[],
    this.categories = const <Category>[],
    this.tab = 0,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<Map<String, Object?>> rows;
  final List<Map<String, Object?>> performance;
  final List<Map<String, Object?>> loyalty;
  final List<Category> categories;
  final int tab;
  final bool busy;
  final Failure? failure;

  PromotionsState copyWith({
    AppStatus? status,
    List<Map<String, Object?>>? rows,
    List<Map<String, Object?>>? performance,
    List<Map<String, Object?>>? loyalty,
    List<Category>? categories,
    int? tab,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      PromotionsState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        performance: performance ?? this.performance,
        loyalty: loyalty ?? this.loyalty,
        categories: categories ?? this.categories,
        tab: tab ?? this.tab,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class PromotionsCubit extends Cubit<PromotionsState> {
  PromotionsCubit({
    required PromotionsRepository promotions,
    required CatalogRepository catalog,
    int? userId,
  })  : _promotions = promotions,
        _catalog = catalog,
        _userId = userId,
        super(const PromotionsState());

  final PromotionsRepository _promotions;
  final CatalogRepository _catalog;
  final int? _userId;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<List<Map<String, Object?>>> rows = await _promotions.all();
    final Result<List<Map<String, Object?>>> perf =
        await _promotions.performance();
    final Result<List<Map<String, Object?>>> points =
        await _promotions.loyaltyBalances();
    final Result<List<Category>> categories = await _catalog.categories();
    if (isClosed) return;

    final Failure? failure = rows.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            rows: rows.valueOrNull,
            performance: perf.valueOr(const <Map<String, Object?>>[]),
            loyalty: points.valueOr(const <Map<String, Object?>>[]),
            categories: categories.valueOr(const <Category>[]),
            clearFailure: true,
          ));
  }

  void setTab(int tab) => emit(state.copyWith(tab: tab));

  Future<bool> save(PromotionDraft draft) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _promotions.save(draft, userId: _userId);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    if (failure != null) return false;
    await load();
    return true;
  }

  Future<void> setActive(int id, bool active) async {
    await _promotions.setActive(id, active, userId: _userId);
    await load();
  }

  Future<bool> remove(int id) async {
    final Result<dynamic> result = await _promotions.remove(id, userId: _userId);
    if (isClosed) return false;
    if (result.failed) {
      emit(state.copyWith(failure: result.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<List<int>> itemsOf(int id) async {
    final Result<List<int>> result = await _promotions.itemsOf(id);
    return result.valueOr(const <int>[]);
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

/// Offers, what they have cost, and who is collecting points.
class PromotionsPage extends StatelessWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PromotionsCubit, PromotionsState>(
      listenWhen: (PromotionsState a, PromotionsState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, PromotionsState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PromotionsCubit>().clearFailure();
      },
      builder: (BuildContext context, PromotionsState state) {
        final PromotionsCubit cubit = context.read<PromotionsCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.promotionsTitle),
                subtitle: '${state.rows.length}',
                actions: <Widget>[
                  FilledButton.icon(
                    onPressed:
                        state.busy ? null : () => _edit(context, cubit, null),
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: Text(context.tr(AppText.promotionsNew)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    label: Text(context.tr(AppText.promotionsTitle)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text(context.tr(AppText.promotionsCost)),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    label: Text(context.tr(AppText.loyaltyTitle)),
                  ),
                ],
                selected: <int>{state.tab},
                onSelectionChanged: (Set<int> s) => cubit.setTab(s.first),
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
                switch (state.tab) {
                  1 => _Performance(rows: state.performance),
                  2 => _Loyalty(rows: state.loyalty),
                  _ => _List(state: state, cubit: cubit),
                },
            ],
          ),
        );
      },
    );
  }

  static Future<void> _edit(
    BuildContext context,
    PromotionsCubit cubit,
    Map<String, Object?>? row,
  ) async {
    final List<int> items =
        row == null ? const <int>[] : await cubit.itemsOf(row['id'] as int);
    if (!context.mounted) return;

    await showAppModal<void>(
      context,
      title: row == null
          ? context.tr(AppText.promotionsNew)
          : '${row['name']}',
      width: 640,
      builder: (BuildContext modalContext) =>
          _PromotionForm(cubit: cubit, row: row, itemIds: items),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.state, required this.cubit});

  final PromotionsState state;
  final PromotionsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<Map<String, Object?>>(
      rows: state.rows,
      onRowTap: (Map<String, Object?> row) =>
          PromotionsPage._edit(context, cubit, row),
      empty: EmptyState(
        icon: Icons.local_offer_outlined,
        message: context.tr(AppText.promotionsEmpty),
      ),
      rowTint: (BuildContext context, Map<String, Object?> row) =>
          (row['is_active'] as int? ?? 0) == 1
              ? null
              : Theme.of(context).surfaces.muted.withValues(alpha: 0.06),
      mobileCard: (BuildContext context, Map<String, Object?> row) =>
          AdminRecordCard(
        title: '${row['name']}',
        subtitle: _describe(context, row),
        onTap: () => PromotionsPage._edit(context, cubit, row),
        trailing: Switch(
          value: (row['is_active'] as int? ?? 0) == 1,
          onChanged: (bool v) => cubit.setActive(row['id'] as int, v),
        ),
      ),
      columns: <AdminColumn<Map<String, Object?>>>[
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.name),
          flex: 4,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text('${row['name']}'),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.promotionsKind),
          flex: 5,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text(_describe(context, row)),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.promotionsWhen),
          flex: 4,
          hideBelow: 1000,
          cell: (BuildContext context, Map<String, Object?> row) => Text(
            <String>[
              if ((row['starts_on'] as String? ?? '').isNotEmpty)
                Fmt.date('${row['starts_on']}'),
              if ((row['ends_on'] as String? ?? '').isNotEmpty)
                Fmt.date('${row['ends_on']}'),
            ].join(' → '),
          ),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.items),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) => Text(
            '${row['scope']}' == 'all'
                ? context.tr(AppText.all)
                : '${row['item_count'] ?? 0}',
          ),
        ),
        AdminColumn<Map<String, Object?>>(
          label: '',
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) => Switch(
            value: (row['is_active'] as int? ?? 0) == 1,
            onChanged: (bool v) => cubit.setActive(row['id'] as int, v),
          ),
        ),
      ],
    );
  }

  /// The rule in one line, in the shop's own words.
  static String _describe(BuildContext context, Map<String, Object?> row) {
    final PromotionKind kind = PromotionKind.fromDb(row['kind']);
    final int bp = row['value_bp'] as int? ?? 0;
    final int minor = row['value_minor'] as int? ?? 0;
    final int minQty = row['min_qty_milli'] as int? ?? 0;
    final int getQty = row['get_qty_milli'] as int? ?? 0;

    return switch (kind) {
      PromotionKind.percent =>
        context.tr(AppText.promotionsOffPercent, params: <String, Object?>{
          'n': '${bp ~/ 100}',
        }),
      PromotionKind.amount =>
        context.tr(AppText.promotionsOffAmount, params: <String, Object?>{
          'amount': Fmt.moneyMinor(minor),
        }),
      PromotionKind.price =>
        context.tr(AppText.promotionsFixedPrice, params: <String, Object?>{
          'amount': Fmt.moneyMinor(minor),
        }),
      PromotionKind.quantity =>
        context.tr(AppText.promotionsFromQty, params: <String, Object?>{
          'qty': Fmt.qtyMilli(minQty),
          'amount': Fmt.moneyMinor(minor),
        }),
      PromotionKind.buyGet =>
        context.tr(AppText.promotionsBuyGet, params: <String, Object?>{
          'buy': Fmt.qtyMilli(minQty),
          'get': Fmt.qtyMilli(getQty),
        }),
    };
  }
}

class _Performance extends StatelessWidget {
  const _Performance({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    return AdminTable<Map<String, Object?>>(
      rows: rows,
      empty: EmptyState(
        icon: Icons.query_stats,
        message: context.tr(AppText.promotionsEmpty),
      ),
      mobileCard: (BuildContext context, Map<String, Object?> row) =>
          AdminRecordCard(
        title: '${row['name']}',
        trailing: Text(Fmt.moneyMinor(row['given_minor'] as int? ?? 0)),
        details: <Widget>[
          RecordDetail(
            label: context.tr(AppText.promotionsGiven),
            value: Fmt.moneyMinor(row['given_minor'] as int? ?? 0),
          ),
          RecordDetail(
            label: context.tr(AppText.profit),
            value: Fmt.moneyMinor(row['profit_minor'] as int? ?? 0),
          ),
        ],
      ),
      columns: <AdminColumn<Map<String, Object?>>>[
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.name),
          flex: 5,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text('${row['name']}'),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.promotionsLines),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text('${row['lines_sold'] ?? 0}'),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.promotionsGiven),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) => Text(
            Fmt.moneyMinor(row['given_minor'] as int? ?? 0),
            style: const TextStyle(color: AppColors.warning),
          ),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.revenue),
          flex: 3,
          alignEnd: true,
          hideBelow: 900,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text(Fmt.moneyMinor(row['revenue_minor'] as int? ?? 0)),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.profit),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) {
            final int profit = row['profit_minor'] as int? ?? 0;
            return Text(
              Fmt.moneyMinor(profit),
              style: TextStyle(
                color: profit < 0 ? AppColors.danger : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Loyalty extends StatelessWidget {
  const _Loyalty({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    return AdminTable<Map<String, Object?>>(
      rows: rows,
      empty: EmptyState(
        icon: Icons.card_giftcard,
        message: context.tr(AppText.loyaltyEmpty),
      ),
      mobileCard: (BuildContext context, Map<String, Object?> row) =>
          AdminRecordCard(
        title: '${row['name']}',
        trailing: Text('${row['points'] ?? 0}'),
      ),
      columns: <AdminColumn<Map<String, Object?>>>[
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.customer),
          flex: 5,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text('${row['name']}'),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.loyaltyPoints),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Map<String, Object?> row) => Text(
            '${row['points'] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        AdminColumn<Map<String, Object?>>(
          label: context.tr(AppText.date),
          flex: 3,
          alignEnd: true,
          hideBelow: 800,
          cell: (BuildContext context, Map<String, Object?> row) =>
              Text(Fmt.dateTime(row['last_activity'] as String?)),
        ),
      ],
    );
  }
}

class _PromotionForm extends StatefulWidget {
  const _PromotionForm({
    required this.cubit,
    required this.row,
    required this.itemIds,
  });

  final PromotionsCubit cubit;
  final Map<String, Object?>? row;
  final List<int> itemIds;

  @override
  State<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends State<_PromotionForm> {
  late final TextEditingController _name =
      TextEditingController(text: '${widget.row?['name'] ?? ''}');
  late final TextEditingController _percent = TextEditingController(
    text: widget.row == null
        ? ''
        : '${(widget.row!['value_bp'] as int? ?? 0) / 100}',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.row == null
        ? ''
        : Fmt.moneyPlain(widget.row!['value_minor'] as int? ?? 0),
  );
  late final TextEditingController _minQty = TextEditingController(
    text: widget.row == null
        ? ''
        : Fmt.qtyMilli(widget.row!['min_qty_milli'] as int? ?? 0),
  );
  late final TextEditingController _getQty = TextEditingController(
    text: widget.row == null
        ? ''
        : Fmt.qtyMilli(widget.row!['get_qty_milli'] as int? ?? 0),
  );

  late PromotionKind _kind = PromotionKind.fromDb(widget.row?['kind']);
  late String _scope = '${widget.row?['scope'] ?? 'items'}';
  late int? _categoryId = widget.row?['category_id'] as int?;
  late bool _membersOnly = (widget.row?['members_only'] as int? ?? 0) == 1;
  late bool _active = (widget.row?['is_active'] as int? ?? 1) == 1;
  late final Set<int> _items = <int>{...widget.itemIds};
  final Map<int, String> _names = <int, String>{};

  final TextEditingController _search = TextEditingController();
  List<Item> _results = const <Item>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _find('');
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _amount.dispose();
    _minQty.dispose();
    _getQty.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _find(String text) async {
    final Result<List<Item>> items =
        await sl<CatalogRepository>().searchItems(text: text, limit: 24);
    if (!mounted) return;
    setState(() {
      _results = items.valueOr(const <Item>[]);
      for (final Item i in _results) {
        _names[i.id] = i.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool needsPercent = _kind == PromotionKind.percent;
    final bool needsAmount = _kind == PromotionKind.amount ||
        _kind == PromotionKind.price ||
        _kind == PromotionKind.quantity;
    final bool needsQty = _kind == PromotionKind.quantity ||
        _kind == PromotionKind.buyGet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(
          controller: _name,
          label: context.tr(AppText.name),
          autofocus: true,
        ),
        const SizedBox(height: 14),
        AppDropdown<PromotionKind>(
          label: context.tr(AppText.promotionsKind),
          value: _kind,
          items: PromotionKind.values,
          itemLabel: (PromotionKind k) => switch (k) {
            PromotionKind.percent => context.tr(AppText.promotionsKindPercent),
            PromotionKind.amount => context.tr(AppText.promotionsKindAmount),
            PromotionKind.price => context.tr(AppText.promotionsKindPrice),
            PromotionKind.quantity => context.tr(AppText.promotionsKindQuantity),
            PromotionKind.buyGet => context.tr(AppText.promotionsKindBuyGet),
          },
          onChanged: (PromotionKind? k) =>
              setState(() => _kind = k ?? PromotionKind.percent),
        ),
        const SizedBox(height: 14),

        if (needsPercent)
          PercentField(
            controller: _percent,
            label: context.tr(AppText.promotionsPercent),
          ),
        if (needsAmount)
          MoneyField(
            controller: _amount,
            label: _kind == PromotionKind.amount
                ? context.tr(AppText.promotionsAmountOff)
                : context.tr(AppText.promotionsNewPrice),
          ),
        if (needsQty) ...<Widget>[
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: QtyField(
                  controller: _minQty,
                  label: _kind == PromotionKind.buyGet
                      ? context.tr(AppText.promotionsBuyQty)
                      : context.tr(AppText.promotionsMinQty),
                ),
              ),
              if (_kind == PromotionKind.buyGet) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: QtyField(
                    controller: _getQty,
                    label: context.tr(AppText.promotionsGetQty),
                  ),
                ),
              ],
            ],
          ),
        ],

        const Divider(height: 26),
        AppDropdown<String>(
          label: context.tr(AppText.promotionsScope),
          value: _scope,
          items: const <String>['items', 'category', 'all'],
          itemLabel: (String s) => switch (s) {
            'category' => context.tr(AppText.category),
            'all' => context.tr(AppText.all),
            _ => context.tr(AppText.items),
          },
          onChanged: (String? s) => setState(() => _scope = s ?? 'items'),
        ),

        if (_scope == 'category') ...<Widget>[
          const SizedBox(height: 14),
          AppDropdown<int>(
            label: context.tr(AppText.category),
            value: _categoryId,
            items: widget.cubit.state.categories.map((Category c) => c.id).toList(),
            itemLabel: (int id) => widget.cubit.state.categories
                .firstWhere((Category c) => c.id == id)
                .name,
            onChanged: (int? id) => setState(() => _categoryId = id),
          ),
        ],

        if (_scope == 'items') ...<Widget>[
          const SizedBox(height: 14),
          AppTextField(
            controller: _search,
            label: context.tr(AppText.search),
            prefixIcon: Icons.search,
            onChanged: _find,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final Item item in _results)
                FilterChip(
                  label: Text(item.name),
                  selected: _items.contains(item.id),
                  onSelected: (bool on) => setState(() {
                    if (on) {
                      _items.add(item.id);
                    } else {
                      _items.remove(item.id);
                    }
                  }),
                ),
            ],
          ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr(AppText.promotionsChosen,
                    params: <String, Object?>{'n': _items.length}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],

        const SizedBox(height: 8),
        AppSwitchTile(
          icon: Icons.card_membership,
          title: context.tr(AppText.promotionsMembersOnly),
          value: _membersOnly,
          onChanged: (bool v) => setState(() => _membersOnly = v),
        ),
        AppSwitchTile(
          icon: Icons.toggle_on_outlined,
          title: context.tr(AppText.active),
          value: _active,
          onChanged: (bool v) => setState(() => _active = v),
        ),

        const SizedBox(height: 18),
        ModalActions(
          busy: _busy,
          onSave: _submit,
          destructive: widget.row == null
              ? null
              : () async {
                  final bool ok = await confirmDelete(context);
                  if (!ok || !context.mounted) return;
                  final bool done =
                      await widget.cubit.remove(widget.row!['id'] as int);
                  if (done && context.mounted) Navigator.of(context).pop();
                },
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);

    final bool ok = await widget.cubit.save(PromotionDraft(
      id: widget.row?['id'] as int?,
      name: _name.text,
      kind: _kind,
      valueBp: Fmt.parsePercentBp(_percent.text) ?? 0,
      valueMinor: (MoneyField.read(_amount) ?? Money.zero).minor,
      minQtyMilli: (Fmt.parseQty(_minQty.text)?.milli) ?? 0,
      getQtyMilli: (Fmt.parseQty(_getQty.text)?.milli) ?? 0,
      scope: _scope,
      categoryId: _categoryId,
      membersOnly: _membersOnly,
      isActive: _active,
      itemIds: _items.toList(),
    ));

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }
}

class PromotionsRoutes {
  const PromotionsRoutes._();

  static const String path = '/promotions';

  static Widget standalone() => Builder(
        builder: (BuildContext context) => BlocProvider<PromotionsCubit>(
          create: (_) => PromotionsCubit(
            promotions: sl<PromotionsRepository>(),
            catalog: sl<CatalogRepository>(),
            userId: context.read<AuthCubit>().state.user?.id,
          )..load(),
          child: const PromotionsPage(),
        ),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
