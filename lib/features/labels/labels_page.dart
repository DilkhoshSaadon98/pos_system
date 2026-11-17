import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/panels.dart';
import '../catalog/domain/entities/catalog_entities.dart';
import '../catalog/domain/repositories/catalog_repository.dart';
import '../printing/domain/repositories/printing_repository.dart';
import 'label_pdf.dart';

/// One row of the print queue: an item and how many labels of it.
class LabelRow {
  const LabelRow({required this.item, this.copies = 1});

  final Item item;
  final int copies;

  LabelRow withCopies(int n) => LabelRow(item: item, copies: n < 1 ? 1 : n);
}

class LabelsState {
  const LabelsState({
    this.status = AppStatus.initial,
    this.results = const <Item>[],
    this.queue = const <LabelRow>[],
    this.size = LabelSize.medium,
    this.showName = true,
    this.showPrice = true,
    this.showShop = false,
    this.columns = 3,
    this.busy = false,
    this.preview,
    this.failure,
  });

  final AppStatus status;

  /// What the search found, to pick from.
  final List<Item> results;

  /// What will be printed.
  final List<LabelRow> queue;

  final LabelSize size;
  final bool showName;
  final bool showPrice;
  final bool showShop;
  final int columns;

  final bool busy;
  final Uint8List? preview;
  final Failure? failure;

  int get labelCount =>
      queue.fold(0, (int sum, LabelRow r) => sum + r.copies);

  LabelsState copyWith({
    AppStatus? status,
    List<Item>? results,
    List<LabelRow>? queue,
    LabelSize? size,
    bool? showName,
    bool? showPrice,
    bool? showShop,
    int? columns,
    bool? busy,
    Uint8List? preview,
    bool clearPreview = false,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      LabelsState(
        status: status ?? this.status,
        results: results ?? this.results,
        queue: queue ?? this.queue,
        size: size ?? this.size,
        showName: showName ?? this.showName,
        showPrice: showPrice ?? this.showPrice,
        showShop: showShop ?? this.showShop,
        columns: columns ?? this.columns,
        busy: busy ?? this.busy,
        preview: clearPreview ? null : (preview ?? this.preview),
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Building a sheet of labels.
class LabelsCubit extends Cubit<LabelsState> {
  LabelsCubit({
    required CatalogRepository catalog,
    required PrintingRepository printing,
    required AppDatabase database,
  })  : _catalog = catalog,
        _printing = printing,
        _database = database,
        super(const LabelsState());

  final CatalogRepository _catalog;
  final PrintingRepository _printing;
  final AppDatabase _database;

  Future<void> load() async {
    emit(state.copyWith(
      status: AppStatus.loading,
      // The shop's saved choices, so a till that prints 50×30 labels every day
      // does not have to be told again every morning.
      size: LabelSize.fromDb(_database.settingString('label_size', '50x30')),
      showName: _database.settingBool('label_show_name', true),
      showPrice: _database.settingBool('label_show_price', true),
      showShop: _database.settingBool('label_show_shop'),
      columns: _database.settingInt('label_columns', 3),
    ));
    await search('');
    if (!isClosed) emit(state.copyWith(status: AppStatus.ready));
  }

  Future<void> search(String text) async {
    final Result<List<Item>> items = await _catalog.searchItems(
      text: text,
      includeVariants: true,
      limit: 60,
    );
    if (isClosed) return;
    emit(state.copyWith(
      results: items.valueOr(const <Item>[]),
      failure: items.failureOrNull,
    ));
  }

  void add(Item item) {
    final int at = state.queue.indexWhere((LabelRow r) => r.item.id == item.id);
    final List<LabelRow> queue = <LabelRow>[...state.queue];
    if (at >= 0) {
      queue[at] = queue[at].withCopies(queue[at].copies + 1);
    } else {
      queue.add(LabelRow(item: item));
    }
    emit(state.copyWith(queue: queue, clearPreview: true));
  }

  void setCopies(int itemId, int copies) {
    final List<LabelRow> queue = <LabelRow>[
      for (final LabelRow r in state.queue)
        if (r.item.id == itemId) r.withCopies(copies) else r,
    ];
    emit(state.copyWith(queue: queue, clearPreview: true));
  }

  void removeRow(int itemId) => emit(state.copyWith(
        queue: state.queue
            .where((LabelRow r) => r.item.id != itemId)
            .toList(growable: false),
        clearPreview: true,
      ));

  void clearQueue() =>
      emit(state.copyWith(queue: const <LabelRow>[], clearPreview: true));

  /// Fills the queue with everything the current search found — the fast way
  /// to relabel a shelf after a price change.
  void addAllResults() {
    final List<LabelRow> queue = <LabelRow>[...state.queue];
    for (final Item item in state.results) {
      if (queue.every((LabelRow r) => r.item.id != item.id)) {
        queue.add(LabelRow(item: item));
      }
    }
    emit(state.copyWith(queue: queue, clearPreview: true));
  }

  void setSize(LabelSize size) {
    emit(state.copyWith(size: size, clearPreview: true));
    _database.setSetting('label_size', size.dbValue);
  }

  void setShowName(bool v) {
    emit(state.copyWith(showName: v, clearPreview: true));
    _database.setSetting('label_show_name', v ? '1' : '0');
  }

  void setShowPrice(bool v) {
    emit(state.copyWith(showPrice: v, clearPreview: true));
    _database.setSetting('label_show_price', v ? '1' : '0');
  }

  void setShowShop(bool v) {
    emit(state.copyWith(showShop: v, clearPreview: true));
    _database.setSetting('label_show_shop', v ? '1' : '0');
  }

  void setColumns(int n) {
    emit(state.copyWith(columns: n, clearPreview: true));
    _database.setSetting('label_columns', '$n');
  }

  Future<void> buildPreview() async {
    if (state.queue.isEmpty) return;
    emit(state.copyWith(busy: true, clearFailure: true));

    final Uint8List bytes = await LabelPdf.build(
      <LabelRequest>[
        for (final LabelRow r in state.queue)
          LabelRequest(
            name: r.item.name,
            priceMinor: r.item.defaultSellPrice.minor,
            code: r.item.primaryBarcode ?? '',
            sku: r.item.sku,
            unitName: r.item.baseUnitName,
            copies: r.copies,
          ),
      ],
      size: state.size,
      shopName: _database.settingString('business_name'),
      showName: state.showName,
      showPrice: state.showPrice,
      showShop: state.showShop,
      columns: state.columns,
    );
    if (isClosed) return;
    emit(state.copyWith(busy: false, preview: bytes));
  }

  /// Hands the sheet to the printer dialog. Labels go to a label printer or an
  /// office printer, never to the thermal receipt path — a receipt printer
  /// cannot cut a die-cut label.
  Future<bool> print() async {
    await buildPreview();
    final Uint8List? bytes = state.preview;
    if (bytes == null) return false;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result =
        await _printing.present(bytes, name: 'labels');
    if (isClosed) return false;

    emit(state.copyWith(busy: false, failure: result.failureOrNull));
    return result.succeeded;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

/// Printing price and barcode labels.
class LabelsPage extends StatefulWidget {
  const LabelsPage({super.key});

  @override
  State<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<LabelsPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LabelsCubit, LabelsState>(
      listenWhen: (LabelsState a, LabelsState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, LabelsState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<LabelsCubit>().clearFailure();
      },
      builder: (BuildContext context, LabelsState state) {
        final LabelsCubit cubit = context.read<LabelsCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.labelsTitle),
                subtitle: '${state.labelCount}',
                actions: <Widget>[
                  if (state.queue.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: cubit.clearQueue,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: Text(context.tr(AppText.clear)),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: state.queue.isEmpty || state.busy
                        ? null
                        : () async {
                            final bool ok = await cubit.print();
                            if (ok && context.mounted) {
                              AppSnack.info(
                                  context, context.tr(AppText.printSent));
                            }
                          },
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(context.tr(AppText.labelsPrint)),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _Options(state: state, cubit: cubit),
              const SizedBox(height: 18),

              AppTextField(
                controller: _search,
                label: context.tr(AppText.search),
                prefixIcon: Icons.search,
                onChanged: cubit.search,
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text(
                    '${state.results.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).surfaces.muted,
                        ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed:
                        state.results.isEmpty ? null : cubit.addAllResults,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: Text(context.tr(AppText.labelsAddAll)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Item item in state.results)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(
                        '${item.name}  ·  ${Fmt.money(item.defaultSellPrice)}',
                      ),
                      onPressed: () => cubit.add(item),
                    ),
                ],
              ),
              const SizedBox(height: 22),

              SectionHeader(
                dense: true,
                title: context.tr(AppText.labelsQueue),
                subtitle: '${state.queue.length}',
              ),
              const SizedBox(height: 10),
              AdminTable<LabelRow>(
                rows: state.queue,
                empty: EmptyState(
                  icon: Icons.qr_code_2,
                  message: context.tr(AppText.labelsEmpty),
                ),
                mobileCard: (BuildContext context, LabelRow row) =>
                    AdminRecordCard(
                  title: row.item.name,
                  subtitle: row.item.primaryBarcode ?? row.item.sku ?? '',
                  trailing: _CopiesField(row: row, cubit: cubit),
                  actions: <Widget>[
                    IconButton(
                      onPressed: () => cubit.removeRow(row.item.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                columns: <AdminColumn<LabelRow>>[
                  AdminColumn<LabelRow>(
                    label: context.tr(AppText.name),
                    flex: 5,
                    cell: (BuildContext context, LabelRow row) =>
                        Text(row.item.name),
                  ),
                  AdminColumn<LabelRow>(
                    label: context.tr(AppText.barcode),
                    flex: 3,
                    hideBelow: 900,
                    cell: (BuildContext context, LabelRow row) =>
                        Text(row.item.primaryBarcode ?? '—'),
                  ),
                  AdminColumn<LabelRow>(
                    label: context.tr(AppText.price),
                    flex: 2,
                    alignEnd: true,
                    cell: (BuildContext context, LabelRow row) =>
                        Text(Fmt.money(row.item.defaultSellPrice)),
                  ),
                  AdminColumn<LabelRow>(
                    label: context.tr(AppText.labelsCopies),
                    flex: 2,
                    alignEnd: true,
                    cell: (BuildContext context, LabelRow row) =>
                        _CopiesField(row: row, cubit: cubit),
                  ),
                  AdminColumn<LabelRow>(
                    label: '',
                    flex: 1,
                    alignEnd: true,
                    cell: (BuildContext context, LabelRow row) => IconButton(
                      tooltip: context.tr(AppText.delete),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => cubit.removeRow(row.item.id),
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
}

class _CopiesField extends StatelessWidget {
  const _CopiesField({required this.row, required this.cubit});

  final LabelRow row;
  final LabelsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 16),
          onPressed: row.copies <= 1
              ? null
              : () => cubit.setCopies(row.item.id, row.copies - 1),
        ),
        Text('${row.copies}'),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 16),
          onPressed: () => cubit.setCopies(row.item.id, row.copies + 1),
        ),
      ],
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.state, required this.cubit});

  final LabelsState state;
  final LabelsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDropdown<LabelSize>(
                    label: context.tr(AppText.labelsSize),
                    value: state.size,
                    items: LabelSize.values,
                    itemLabel: (LabelSize s) => s.isSheet
                        ? context.tr(AppText.labelsSizeSheet)
                        : '${s.widthMm.toInt()} × ${s.heightMm.toInt()} mm',
                    onChanged: (LabelSize? s) =>
                        cubit.setSize(s ?? LabelSize.medium),
                  ),
                ),
                if (state.size.isSheet) ...<Widget>[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<int>(
                      label: context.tr(AppText.labelsColumns),
                      value: state.columns,
                      items: const <int>[2, 3, 4, 5],
                      itemLabel: (int n) => '$n',
                      onChanged: (int? n) => cubit.setColumns(n ?? 3),
                    ),
                  ),
                ],
              ],
            ),
            AppSwitchTile(
              icon: Icons.label_outline,
              title: context.tr(AppText.labelsShowName),
              value: state.showName,
              onChanged: cubit.setShowName,
            ),
            AppSwitchTile(
              icon: Icons.sell_outlined,
              title: context.tr(AppText.labelsShowPrice),
              value: state.showPrice,
              onChanged: cubit.setShowPrice,
            ),
            AppSwitchTile(
              icon: Icons.storefront_outlined,
              title: context.tr(AppText.labelsShowShop),
              value: state.showShop,
              onChanged: cubit.setShowShop,
            ),
          ],
        ),
      ),
    );
  }
}

class LabelsRoutes {
  const LabelsRoutes._();

  static const String path = '/labels';

  static Widget standalone() => BlocProvider<LabelsCubit>(
        create: (_) => LabelsCubit(
          catalog: sl<CatalogRepository>(),
          printing: sl<PrintingRepository>(),
          database: sl<AppDatabase>(),
        )..load(),
        child: const LabelsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
