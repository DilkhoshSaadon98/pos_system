import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/panels.dart';
import '../../../../core/widgets/stored_image.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';

class PosItemGrid extends StatelessWidget {
  const PosItemGrid({
    super.key,
    required this.items,
    required this.priceMode,
    required this.onTap,
    this.loading = false,
  });

  final List<Item> items;
  final PriceMode priceMode;
  final void Function(Item item) onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !loading) {
      return EmptyState(
        icon: Icons.search_off,
        message: context.tr(AppText.posGridEmpty),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = Responsive.posGridColumns(constraints.maxWidth);

        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) => _Tile(
            item: items[index],
            priceMode: priceMode,
            onTap: () => onTap(items[index]),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.priceMode,
    required this.onTap,
  });

  final Item item;
  final PriceMode priceMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = switch (item.kind) {
      ItemKind.service => AppColors.info,
      ItemKind.bundle => AppColors.tileTints[3],
      ItemKind.group => AppColors.tileTints[5],
      ItemKind.stock => AppColors.tintFor(item.id),
    };

    final bool blocked = item.isOutOfStock && !item.allowNegative;
    final ItemUnit? unit = item.saleUnit;
    final String price = item.isGroup
        ? '—'
        : Fmt.money(unit?.priceFor(priceMode) ?? item.defaultSellPrice);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: blocked
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : theme.surfaces.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    StoredImage(
                      name: item.imagePath,
                      radius: 0,
                      tint: tint,
                      icon: switch (item.kind) {
                        ItemKind.service => Icons.handyman_outlined,
                        ItemKind.bundle => Icons.widgets_outlined,
                        ItemKind.group => Icons.category_outlined,
                        ItemKind.stock => item.isWeighed
                            ? Icons.scale_outlined
                            : Icons.inventory_2_outlined,
                      },
                    ),
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: _Badge(item: item),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary)
                          .merge(theme.tabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    if (item.isGroup) {
      return StatusChip(
        compact: true,
        label: '${item.variantCount}',
        color: AppColors.tileTints[5],
        icon: Icons.category_outlined,
      );
    }
    if (item.isService) {
      return StatusChip(
        compact: true,
        label: context.tr(AppText.itemsKindService),
        color: AppColors.info,
      );
    }
    if (item.isBundle) {
      return StatusChip(
        compact: true,
        label: '${item.componentCount}',
        color: AppColors.tileTints[3],
        icon: Icons.widgets_outlined,
      );
    }
    if (!item.trackStock) return const SizedBox.shrink();

    return StatusChip(
      compact: true,
      label: Fmt.qtyMilli(item.stockQtyMilli),
      color: item.isOutOfStock
          ? AppColors.danger
          : item.isLowStock
              ? AppColors.warning
              : AppColors.ok,
      filled: item.isOutOfStock,
    );
  }
}
