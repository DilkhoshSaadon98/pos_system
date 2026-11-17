import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
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
import '../../../../core/widgets/stored_image.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../cubit/items_cubit.dart';
import 'bundle_editor.dart';
import 'item_kind_picker.dart';
import 'item_picker.dart';
import 'units_editor.dart';
import 'variants_editor.dart';

/// Opens the item editor for a new item, or for [itemId].
Future<void> showItemEditor({
  required BuildContext context,
  required ItemsCubit cubit,
  int? itemId,
}) async {
  final ItemDraft? draft = await cubit.loadDraft(itemId);
  if (draft == null || !context.mounted) return;

  await showAppModal<void>(
    context,
    width: 760,
    title: context.tr(itemId == null ? AppText.itemsNew : AppText.itemsEdit),
    subtitle: draft.item?.displayName,
    builder: (BuildContext modalContext) => _ItemForm(
      cubit: cubit,
      draft: draft,
    ),
  );
}

/// One form for four kinds of thing.
///
/// The kind is chosen first and the rest of the form follows it: a service
/// never asks about stock, a group never asks for a price, a bundle asks what
/// is in it. Hiding what does not apply is not cosmetic — a form that offers a
/// reorder level for a delivery charge invites somebody to fill it in.
class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.cubit, required this.draft});

  final ItemsCubit cubit;
  final ItemDraft draft;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _description;
  late final TextEditingController _reorder;
  late final TextEditingController _tax;
  late final TextEditingController _scaleCode;
  late final TextEditingController _openingQty;
  late final TextEditingController _openingCost;

  late ItemKind _kind;
  late List<ItemUnit> _units;
  late List<VariantAxis> _axes;
  late List<BundlePart> _parts;
  int? _categoryId;
  int? _baseUnitId;
  String? _imagePath;
  late bool _trackStock;
  late bool _allowNegative;
  late bool _isActive;
  late bool _isWeighed;
  late bool _trackBatches;
  DateTime? _expiry;

  bool _saving = false;
  int _tab = 0;

  Item? get _item => widget.draft.item;
  bool get _isNew => _item == null;

  /// The kind cannot change once the item has moved: the ledger already
  /// describes it as what it was.
  bool get _kindLocked => !_isNew && _item!.stockQtyMilli != 0;

  @override
  void initState() {
    super.initState();
    final Item? item = _item;

    _name = TextEditingController(text: item?.variantName ?? item?.name ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _description = TextEditingController(text: item?.description ?? '');
    _reorder = TextEditingController(
      text: (item?.reorderLevelMilli ?? 0) == 0
          ? ''
          : Fmt.qtyMilli(item!.reorderLevelMilli),
    );
    _tax = TextEditingController(
      text: (item?.taxRateBp ?? 0) == 0 ? '' : '${item!.taxRateBp / 100}',
    );
    _scaleCode = TextEditingController(text: item?.scaleCode ?? '');
    _openingQty = TextEditingController();
    _openingCost = TextEditingController();

    _kind = item?.kind ?? ItemKind.stock;
    _units = List<ItemUnit>.from(widget.draft.units);
    _axes = List<VariantAxis>.from(widget.draft.axes);
    _parts = List<BundlePart>.from(widget.draft.parts);
    _categoryId = item?.categoryId;
    _baseUnitId = item?.baseUnitId;
    _imagePath = item?.imagePath;
    _trackStock = item?.trackStock ?? true;
    _allowNegative = item?.allowNegative ?? false;
    _isActive = item?.isActive ?? true;
    _isWeighed = item?.isWeighed ?? false;
    _trackBatches = item?.trackBatches ?? false;
    _expiry = item?.expiryDate == null ? null : DateTime.tryParse(item!.expiryDate!);

    // A brand new item starts with one unit so the form is usable straight
    // away; the first unit in the library is almost always "Piece".
    final List<UnitDef> library = widget.cubit.state.units;
    if (_units.isEmpty && library.isNotEmpty) {
      _baseUnitId ??= library.first.id;
      _units = <ItemUnit>[
        ItemUnit(
          id: null,
          itemId: 0,
          unitId: library.first.id,
          unitName: library.first.name,
          factorMilli: 1000,
          sellPrice: Money.zero,
          wholesalePrice: Money.zero,
          minPrice: Money.zero,
          isBase: true,
          isDefaultSale: true,
          isDefaultPurchase: true,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _description.dispose();
    _reorder.dispose();
    _tax.dispose();
    _scaleCode.dispose();
    _openingQty.dispose();
    _openingCost.dispose();
    super.dispose();
  }

  List<_Tab> get _tabs => <_Tab>[
        _Tab(AppText.itemsGeneral, Icons.info_outline),
        if (_kind != ItemKind.group)
          _Tab(AppText.itemsPricing, Icons.sell_outlined),
        if (_kind == ItemKind.group)
          _Tab(AppText.itemsVariants, Icons.category_outlined),
        if (_kind == ItemKind.bundle)
          _Tab(AppText.itemsBundleComponents, Icons.widgets_outlined),
        if (_kind == ItemKind.stock)
          _Tab(AppText.itemsStockTab, Icons.inventory_outlined),
        // Only for an item that exists: a new one has no past.
        if (!_isNew) _Tab(AppText.priceHistory, Icons.history),
      ];

  @override
  Widget build(BuildContext context) {
    final List<_Tab> tabs = _tabs;
    final int tab = _tab.clamp(0, tabs.length - 1);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ItemKindPicker(
            value: _kind,
            locked: _kindLocked,
            onChanged: (ItemKind k) => setState(() {
              _kind = k;
              _tab = 0;
              // A service is never counted, and a bundle's stock lives in its
              // parts. Reflecting that here keeps the form honest before the
              // repository has to enforce it.
              if (k != ItemKind.stock) _trackStock = false;
              if (k == ItemKind.stock) _trackStock = true;
            }),
          ),
          const SizedBox(height: 20),
          _TabBar(
            tabs: tabs,
            index: tab,
            onChanged: (int i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 18),
          _buildTab(tabs[tab].labelKey),
          const SizedBox(height: 24),
          ModalActions(
            busy: _saving,
            onSave: _save,
            destructive: _isNew ? null : _delete,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String key) => switch (key) {
        AppText.priceHistory => _HistoryTab(
            cubit: widget.cubit,
            itemId: _item!.id,
          ),
        AppText.itemsPricing => UnitsEditor(
            rows: _units,
            available: widget.cubit.state.units,
            avgCost: _item?.avgCost ?? Money.zero,
            onChanged: (List<ItemUnit> u) => setState(() {
              _units = u;
              final ItemUnit? base = u.where((ItemUnit e) => e.isBase).isEmpty
                  ? null
                  : u.firstWhere((ItemUnit e) => e.isBase);
              if (base != null) _baseUnitId = base.unitId;
            }),
          ),
        AppText.itemsVariants => VariantAxesEditor(
            axes: _axes,
            variants: widget.draft.variants,
            busy: _saving,
            onChanged: (List<VariantAxis> a) => setState(() => _axes = a),
            onGenerate: _isNew ? null : _generate,
          ),
        AppText.itemsBundleComponents => BundlePartsEditor(
            parts: _parts,
            sellPrice: _units.isEmpty ? Money.zero : _units.first.sellPrice,
            onPick: () => showItemPicker(
              context,
              title: AppText.itemsAddComponent,
              search: (String text) => widget.cubit
                  .lookup(text, kinds: bundleComponentKinds),
            ),
            onChanged: (List<BundlePart> p) => setState(() => _parts = p),
          ),
        AppText.itemsStockTab => _StockTab(
            reorder: _reorder,
            openingQty: _openingQty,
            openingCost: _openingCost,
            allowNegative: _allowNegative,
            trackStock: _trackStock,
            showOpening: _isNew,
            baseUnitName: _baseUnitName,
            currentStock: _item?.stockQtyMilli ?? 0,
            avgCost: _item?.avgCost ?? Money.zero,
            onTrackStock: (bool v) => setState(() => _trackStock = v),
            onAllowNegative: (bool v) => setState(() => _allowNegative = v),
          ),
        _ => _generalTab(),
      };

  String get _baseUnitName {
    for (final ItemUnit u in _units) {
      if (u.isBase) return u.unitName;
    }
    return _item?.baseUnitName ?? '';
  }

  Widget _generalTab() {
    final bool isVariant = _item?.isVariant ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isVariant) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).surfaces.raised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.subdirectory_arrow_right, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${context.tr(AppText.itemsVariantOf)}: ${_item!.parentName ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The photo sits where the eye starts, not on a tab of its own:
            // an item with no picture is the commonest thing in the catalogue
            // and the empty square is the reminder to fix it.
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14, top: 4),
              child: ImagePickerField(
                name: _imagePath,
                prefix: 'item',
                onChanged: (String? name) => setState(() => _imagePath = name),
              ),
            ),
            Expanded(
              child: AppTextField(
                controller: _name,
                autofocus: true,
                label: context.tr(AppText.name),
                prefixIcon: Icons.label_outline,
                validator: (String? v) => (v ?? '').trim().isEmpty
                    ? context.tr(AppText.requiredField)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: _sku,
                label: context.tr(AppText.sku),
                prefixIcon: Icons.tag,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppDropdown<int>(
                label: context.tr(AppText.category),
                value: _categoryId,
                items: widget.cubit.state.categories
                    .map((Category c) => c.id)
                    .toList(),
                itemLabel: (int id) => widget.cubit.state.categoryName(id),
                onChanged: (int? id) => setState(() => _categoryId = id),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _description,
          label: context.tr(AppText.description),
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: PercentField(
                controller: _tax,
                label: context.tr(AppText.itemsTaxRate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                label: context.tr(AppText.itemsExpiry),
                value: _expiry,
                clearable: true,
                onChanged: (DateTime? d) => setState(() => _expiry = d),
              ),
            ),
          ],
        ),
        if (_kind == ItemKind.stock) ...<Widget>[
          const SizedBox(height: 8),
          AppSwitchTile(
            icon: Icons.scale_outlined,
            title: context.tr(AppText.itemsWeighed),
            subtitle: context.tr(AppText.itemsWeighedHint),
            value: _isWeighed,
            onChanged: (bool v) => setState(() => _isWeighed = v),
          ),
          // Only offered for stocked goods: a batch is a physical box with a
          // date on it, and a service has neither.
          AppSwitchTile(
            icon: Icons.event_busy_outlined,
            title: context.tr(AppText.itemsTracksBatches),
            value: _trackBatches,
            onChanged: (bool v) => setState(() => _trackBatches = v),
          ),
          if (_isWeighed)
            AppTextField(
              controller: _scaleCode,
              label: context.tr(AppText.itemsScaleCode),
              prefixIcon: Icons.qr_code_scanner,
              keyboardType: TextInputType.number,
              helper: context.tr(AppText.settingsScaleHint),
            ),
        ],
        const SizedBox(height: 8),
        AppSwitchTile(
          icon: Icons.visibility_outlined,
          title: context.tr(AppText.active),
          value: _isActive,
          onChanged: (bool v) => setState(() => _isActive = v),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- actions --

  Future<void> _generate() async {
    setState(() => _saving = true);
    final int? created = await widget.cubit.generateVariants(_item!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (created == null) {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
      return;
    }
    AppSnack.success(context, '$created  ${context.tr(AppText.itemsVariants)}');
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _tab = 0);
      return;
    }

    setState(() => _saving = true);

    final Item? item = _item;
    final bool isVariant = item?.isVariant ?? false;

    final ItemSaveRequest request = ItemSaveRequest(
      id: item?.id,
      // A variant keeps its parent's product name; the box on this form is its
      // own label ("Red / L"), which is what makes the receipt readable.
      name: isVariant ? item!.name : _name.text,
      variantName: isVariant ? _name.text : null,
      variantAttrs: item?.variantAttrs ?? const <String, String>{},
      parentItemId: item?.parentItemId,
      kind: _kind,
      baseUnitId: _baseUnitId ?? item?.baseUnitId ?? 0,
      units: _kind == ItemKind.group ? const <ItemUnit>[] : _units,
      axes: _axes,
      parts: _parts,
      sku: _sku.text,
      categoryId: _categoryId,
      description: _description.text,
      imagePath: _imagePath,
      taxRateBp: PercentField.read(_tax) ?? 0,
      reorderLevelMilli: QtyField.read(_reorder)?.milli ?? 0,
      trackStock: _trackStock,
      allowNegative: _allowNegative,
      expiryDate: _expiry == null
          ? null
          : _expiry!.toIso8601String().substring(0, 10),
      isActive: _isActive,
      isWeighed: _isWeighed,
      trackBatches: _trackBatches,
      scaleCode: _scaleCode.text,
      openingCost: _isNew ? MoneyField.read(_openingCost) : null,
    );

    final int? savedId = await widget.cubit.saveItem(request);
    if (!mounted) return;

    if (savedId == null) {
      setState(() => _saving = false);
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
      return;
    }

    // Opening stock is a second, separate act: it writes a movement and posts
    // to the books, so it only happens once the item exists and only when a
    // figure was actually typed.
    final Qty? opening = _isNew ? QtyField.read(_openingQty) : null;
    if (opening != null && opening.isPositive) {
      await widget.cubit.adjustStock(
        itemId: savedId,
        counted: opening,
        isOpening: true,
        note: 'Opening stock',
      );
    }

    if (!mounted) return;
    AppSnack.success(context, context.tr(AppText.saved));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, what: _item!.displayName)) return;
    final bool ok = await widget.cubit.removeItem(_item!.id);
    if (!mounted) return;
    if (ok) {
      AppSnack.success(context, context.tr(AppText.deleted));
      Navigator.of(context).pop();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}

class _Tab {
  const _Tab(this.labelKey, this.icon);

  final String labelKey;
  final IconData icon;
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index ? theme.cardColor : null,
                    borderRadius: BorderRadius.circular(9),
                    border: i == index
                        ? Border.all(color: theme.surfaces.hairline)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        tabs[i].icon,
                        size: 16,
                        color: i == index
                            ? theme.colorScheme.primary
                            : theme.surfaces.muted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          context.tr(tabs[i].labelKey),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: i == index ? null : theme.surfaces.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StockTab extends StatelessWidget {
  const _StockTab({
    required this.reorder,
    required this.openingQty,
    required this.openingCost,
    required this.allowNegative,
    required this.trackStock,
    required this.showOpening,
    required this.baseUnitName,
    required this.currentStock,
    required this.avgCost,
    required this.onTrackStock,
    required this.onAllowNegative,
  });

  final TextEditingController reorder;
  final TextEditingController openingQty;
  final TextEditingController openingCost;
  final bool allowNegative;
  final bool trackStock;
  final bool showOpening;
  final String baseUnitName;
  final int currentStock;
  final Money avgCost;
  final ValueChanged<bool> onTrackStock;
  final ValueChanged<bool> onAllowNegative;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!showOpening) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: KpiCard(
                  icon: Icons.inventory_outlined,
                  label: context.tr(AppText.stock),
                  value: '${Fmt.qtyMilli(currentStock)} $baseUnitName',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  icon: Icons.payments_outlined,
                  label: context.tr(AppText.itemsAvgCost),
                  value: Fmt.money(avgCost),
                  footnote: context.tr(AppText.itemsStockValue) +
                      ': ' +
                      Fmt.moneyMinor((currentStock * avgCost.minor) ~/ 1000),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        AppSwitchTile(
          icon: Icons.checklist_outlined,
          title: context.tr(AppText.itemsTrackStock),
          value: trackStock,
          onChanged: onTrackStock,
        ),
        AppSwitchTile(
          icon: Icons.trending_down,
          title: context.tr(AppText.itemsAllowNegative),
          value: allowNegative,
          onChanged: onAllowNegative,
        ),
        const SizedBox(height: 8),
        QtyField(
          controller: reorder,
          label: context.tr(AppText.itemsReorder),
          unitName: baseUnitName,
          helper: context.tr(AppText.dashLowStockItems),
        ),
        if (showOpening) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(
            dense: true,
            title: context.tr(AppText.itemsOpeningStock),
            subtitle: context.tr(AppText.itemsAvgCost),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: QtyField(
                  controller: openingQty,
                  label: context.tr(AppText.quantity),
                  unitName: baseUnitName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MoneyField(
                  controller: openingCost,
                  label: context.tr(AppText.itemsAvgCost),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// What this item has been worth, and what it has cost.
///
/// Two lists rather than a chart. A shop with four price changes in a year
/// does not need a line graph; it needs to see the four dates, the two
/// numbers, and the name of whoever typed them — which is the whole reason
/// this trail exists.
class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.cubit, required this.itemId});

  final ItemsCubit cubit;
  final int itemId;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  late Future<ItemHistory> _future = widget.cubit.history(widget.itemId);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return FutureBuilder<ItemHistory>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<ItemHistory> snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final ItemHistory history = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(dense: true, title: context.tr(AppText.priceHistory)),
            const SizedBox(height: 8),
            if (history.prices.isEmpty)
              Text(
                context.tr(AppText.priceHistoryNone),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.surfaces.muted),
              )
            else
              for (final PriceChange change in history.prices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 92,
                        child: Text(
                          _fieldLabel(context, change.field),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        Fmt.money(change.oldPrice),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.surfaces.muted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: theme.surfaces.muted,
                      ),
                      Text(
                        Fmt.money(change.newPrice),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: change.isRise
                              ? AppColors.ok
                              : AppColors.warning,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        <String?>[
                          change.unitName,
                          change.userName,
                          Fmt.date(change.changedAt),
                        ].whereType<String>().join('  ·  '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.surfaces.muted),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 22),
            SectionHeader(dense: true, title: context.tr(AppText.costHistory)),
            const SizedBox(height: 8),
            if (history.costs.isEmpty)
              Text(
                context.tr(AppText.nothingYet),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.surfaces.muted),
              )
            else
              for (final CostPoint point in history.costs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 92,
                        child: Text(
                          Fmt.qtyMilli(point.qtyMilli),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        Fmt.money(point.unitCost),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        <String?>[
                          point.partyName,
                          Fmt.date(point.movedAt),
                        ].whereType<String>().join('  ·  '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.surfaces.muted),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }

  static String _fieldLabel(BuildContext context, String field) =>
      switch (field) {
        'sell' => context.tr(AppText.priceFieldSell),
        'wholesale' => context.tr(AppText.priceFieldWholesale),
        'min' => context.tr(AppText.priceFieldMin),
        _ => field,
      };
}
