import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../../core/widgets/stored_image.dart';
import '../../domain/entities/catalog_entities.dart';
import '../cubit/items_cubit.dart';
import '../cubit/items_state.dart';
import '../widgets/category_manager_sheet.dart';
import '../widgets/item_form_sheet.dart';
import '../widgets/stock_adjust_sheet.dart';
import '../widgets/unit_manager_sheet.dart';

/// The catalogue.
///
/// One screen for four kinds of thing — a stocked product, a service, a bundle
/// and a product with variants — because a shopkeeper does not think of them as
/// four screens. The kind is a badge on the row and a choice at the top of the
/// editor, and everything else follows from it.
class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ItemsCubit, ItemsState>(
      listenWhen: (ItemsState a, ItemsState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, ItemsState state) {
        // A failure while the table already has content belongs in a snack bar,
        // not in place of the table — the cashier can still work.
        AppSnack.error(context, state.failure!.detail);
        context.read<ItemsCubit>().clearFailure();
      },
      builder: (BuildContext context, ItemsState state) {
        final ItemsCubit cubit = context.read<ItemsCubit>();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Responsive.isMobile(context)
              ? FloatingActionButton.extended(
                  onPressed: () => _openEditor(context, cubit, null),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr(AppText.itemsNew)),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Responsive.isMobile(context) ? 14 : 24,
                20,
                Responsive.isMobile(context) ? 14 : 24,
                90,
              ),
              children: <Widget>[
                SectionHeader(
                  title: context.tr(AppText.itemsTitle),
                  subtitle: _subtitle(context, state),
                  actions: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => showCategoryManager(context, cubit),
                      icon: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(context.tr(AppText.itemsCategories)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showUnitManager(context, cubit),
                      icon: const Icon(Icons.straighten_outlined, size: 18),
                      label: Text(context.tr(AppText.itemsUnitsLibrary)),
                    ),
                    if (!Responsive.isMobile(context))
                      FilledButton.icon(
                        onPressed: () => _openEditor(context, cubit, null),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.tr(AppText.itemsNew)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _Filters(state: state, cubit: cubit),
                const SizedBox(height: 18),
                if (state.status.isBusyFirstTime)
                  const _TableSkeleton()
                else if (state.status.isFailure && state.failure != null)
                  ErrorNotice(failure: state.failure!, onRetry: cubit.load)
                else
                  _ItemsTable(state: state, cubit: cubit),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _subtitle(BuildContext context, ItemsState state) {
    if (!state.status.isReady) return context.tr(AppText.loading);
    final List<String> parts = <String>[
      '${state.items.length} ${context.tr(AppText.items).toLowerCase()}',
      '${context.tr(AppText.itemsStockValue)}: ${Fmt.money(state.stockValue)}',
    ];
    if (state.lowStockCount > 0) {
      parts.add(
        '${state.lowStockCount} ${context.tr(AppText.itemsFilterLow).toLowerCase()}',
      );
    }
    return parts.join('  ·  ');
  }
}

Future<void> _openEditor(
  BuildContext context,
  ItemsCubit cubit,
  Item? item,
) =>
    showItemEditor(context: context, cubit: cubit, itemId: item?.id);

class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.cubit});

  final ItemsState state;
  final ItemsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    onChanged: cubit.search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.tr(AppText.search),
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!Responsive.isMobile(context))
                  SegmentedButton<StockFilter>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<StockFilter>>[
                      for (final StockFilter f in StockFilter.values)
                        ButtonSegment<StockFilter>(
                          value: f,
                          label: Text(context.tr(f.labelKey)),
                        ),
                    ],
                    selected: <StockFilter>{state.filter},
                    onSelectionChanged: (Set<StockFilter> s) =>
                        cubit.filterByStock(s.first),
                  ),
              ],
            ),
            if (Responsive.isMobile(context)) ...<Widget>[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final StockFilter f in StockFilter.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(context.tr(f.labelKey)),
                          selected: state.filter == f,
                          onSelected: (_) => cubit.filterByStock(f),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (state.categories.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.surfaces.hairline),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(context.tr(AppText.all)),
                        selected: state.categoryId == null,
                        onSelected: (_) => cubit.filterByCategory(null),
                      ),
                    ),
                    for (final Category c in state.categories)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text('${c.name}  ·  ${c.itemCount}'),
                          selected: state.categoryId == c.id,
                          onSelected: (_) => cubit.filterByCategory(c.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.state, required this.cubit});

  final ItemsState state;
  final ItemsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<Item>(
      rows: state.items,
      onRowTap: (Item row) => _openEditor(context, cubit, row),
      rowTint: (BuildContext context, Item row) => row.isActive
          ? null
          : Theme.of(context).surfaces.overlay,
      empty: EmptyState(
        message: state.query.trim().isEmpty
            ? context.tr(AppText.nothingYet)
            : context.tr(AppText.noResults),
        icon: Icons.inventory_2_outlined,
        action: FilledButton.icon(
          onPressed: () => _openEditor(context, cubit, null),
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.tr(AppText.itemsNew)),
        ),
      ),
      columns: <AdminColumn<Item>>[
        AdminColumn<Item>(
          label: context.tr(AppText.item),
          flex: 5,
          cell: (BuildContext context, Item row) => _NameCell(item: row),
        ),
        AdminColumn<Item>(
          label: context.tr(AppText.category),
          flex: 2,
          hideBelow: 1100,
          cell: (BuildContext context, Item row) => Text(
            row.categoryName ?? '—',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AdminColumn<Item>(
          label: context.tr(AppText.price),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Item row) => Text(
            row.isGroup ? '—' : Fmt.money(row.defaultSellPrice),
            style: Theme.of(context).textTheme.bodyMedium?.merge(
                  Theme.of(context).tabular,
                ),
          ),
        ),
        AdminColumn<Item>(
          label: context.tr(AppText.cost),
          flex: 2,
          alignEnd: true,
          hideBelow: 1300,
          cell: (BuildContext context, Item row) => Text(
            row.isGroup ? '—' : Fmt.money(row.effectiveCost),
            style: Theme.of(context).textTheme.bodySmall?.merge(
                  Theme.of(context).tabular,
                ),
          ),
        ),
        AdminColumn<Item>(
          label: context.tr(AppText.stock),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Item row) => _StockCell(item: row),
        ),
        AdminColumn<Item>(
          label: context.tr(AppText.actions),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Item row) =>
              _RowActions(item: row, cubit: cubit),
        ),
      ],
      mobileCard: (BuildContext context, Item row) => AdminRecordCard(
        onTap: () => _openEditor(context, cubit, row),
        leading: _KindBadge(item: row),
        title: row.displayName,
        subtitle: <String?>[
          row.categoryName,
          row.sku,
        ].whereType<String>().where((String s) => s.isNotEmpty).join('  ·  '),
        trailing: _StockCell(item: row),
        details: <Widget>[
          if (!row.isGroup)
            RecordDetail(
              label: context.tr(AppText.price),
              value: Fmt.money(row.defaultSellPrice),
            ),
          if (!row.isGroup)
            RecordDetail(
              label: context.tr(AppText.cost),
              value: Fmt.money(row.effectiveCost),
            ),
          if (row.isGroup)
            RecordDetail(
              label: context.tr(AppText.itemsVariants),
              value: '${row.variantCount}',
            ),
        ],
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => _openEditor(context, cubit, row),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.tr(AppText.edit)),
          ),
          if (row.kind == ItemKind.stock)
            TextButton.icon(
              onPressed: () => showStockAdjust(context, cubit, row),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(context.tr(AppText.stockAdjust)),
            ),
        ],
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        _KindBadge(item: item),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      item.displayName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            item.isActive ? null : TextDecoration.lineThrough,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.isWeighed) ...<Widget>[
                    const SizedBox(width: 6),
                    Icon(Icons.scale_outlined,
                        size: 15, color: theme.surfaces.muted),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                <String>[
                  if ((item.sku ?? '').isNotEmpty) item.sku!,
                  if ((item.primaryBarcode ?? '').isNotEmpty)
                    item.primaryBarcode!,
                  if (item.isGroup)
                    '${item.variantCount} ${context.tr(AppText.itemsVariants).toLowerCase()}',
                  if (item.isBundle)
                    '${item.componentCount} ${context.tr(AppText.items).toLowerCase()}',
                  if (item.units.length > 1)
                    '${item.units.length} ${context.tr(AppText.unit).toLowerCase()}',
                ].join('  ·  '),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A square of colour with the item's initial — the fastest way to tell four
/// kinds of thing apart in a long list, and it works before a shop has taken a
/// single photograph.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final Color tint = switch (item.kind) {
      ItemKind.service => AppColors.info,
      ItemKind.bundle => AppColors.tileTints[3],
      ItemKind.group => AppColors.tileTints[5],
      ItemKind.stock => AppColors.tintFor(item.id),
    };
    final IconData? icon = switch (item.kind) {
      ItemKind.service => Icons.handyman_outlined,
      ItemKind.bundle => Icons.widgets_outlined,
      ItemKind.group => Icons.category_outlined,
      ItemKind.stock => null,
    };

    return StoredImage(
      name: item.imagePath,
      size: 38,
      tint: tint,
      icon: icon,
      letter: icon != null || item.name.characters.isEmpty
          ? null
          : item.name.characters.first.toUpperCase(),
    );
  }
}

class _StockCell extends StatelessWidget {
  const _StockCell({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    if (item.isService) {
      return StatusChip.neutral(context, context.tr(AppText.itemsKindService));
    }
    if (item.isGroup) {
      return StatusChip.neutral(
        context,
        '${Fmt.qtyMilli(item.variantsStockMilli)} ${item.baseUnitName}',
      );
    }
    if (item.isBundle) {
      return StatusChip(
        label: context.tr(AppText.itemsKindBundle),
        color: AppColors.tileTints[3],
        compact: true,
      );
    }
    if (!item.trackStock) {
      return StatusChip.neutral(context, '—');
    }

    final Color color = item.isOutOfStock
        ? AppColors.danger
        : item.isLowStock
            ? AppColors.warning
            : AppColors.ok;

    return StatusChip(
      label: '${Fmt.qtyMilli(item.stockQtyMilli)} ${item.baseUnitName}',
      color: color,
      compact: true,
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.item, required this.cubit});

  final Item item;
  final ItemsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (item.kind == ItemKind.stock)
          IconButton(
            tooltip: context.tr(AppText.stockAdjust),
            icon: const Icon(Icons.tune, size: 19),
            onPressed: () => showStockAdjust(context, cubit, item),
          ),
        if (item.isGroup)
          IconButton(
            tooltip: context.tr(AppText.itemsGenerateVariants),
            icon: const Icon(Icons.auto_awesome_motion_outlined, size: 19),
            onPressed: () async {
              final int? created = await cubit.generateVariants(item.id);
              if (created != null && context.mounted) {
                AppSnack.success(
                  context,
                  '$created  ${context.tr(AppText.itemsVariants)}',
                );
              }
            },
          ),
        PopupMenuButton<String>(
          tooltip: context.tr(AppText.actions),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'edit',
              child: Text(context.tr(AppText.edit)),
            ),
            PopupMenuItem<String>(
              value: 'toggle',
              child: Text(
                item.isActive
                    ? context.tr(AppText.itemsFilterInactive)
                    : context.tr(AppText.active),
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Text(
                context.tr(AppText.delete),
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ],
          onSelected: (String action) async {
            switch (action) {
              case 'edit':
                await _openEditor(context, cubit, item);
              case 'toggle':
                await cubit.toggleActive(item);
              case 'delete':
                if (await confirmDelete(context, what: item.displayName)) {
                  await cubit.removeItem(item.id);
                }
            }
          },
        ),
      ],
    );
  }
}

/// Grey bars where the table will be. Shown instead of a spinner because a
/// table that appears in place is far less jarring than one that pops in.
class _TableSkeleton extends StatelessWidget {
  const _TableSkeleton();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.surfaces.raised,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: theme.surfaces.raised,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: theme.surfaces.raised,
                          borderRadius: BorderRadius.circular(6),
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
