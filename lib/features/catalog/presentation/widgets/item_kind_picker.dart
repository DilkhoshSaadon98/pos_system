import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';

/// The first decision in the item editor: what sort of thing is this?
///
/// Four cards rather than a dropdown, because the choice changes what the rest
/// of the form asks for and a shopkeeper should be able to see the difference
/// before making it. Each card says, in one line, what the kind means for
/// stock — which is the only thing that actually differs between them.
class ItemKindPicker extends StatelessWidget {
  const ItemKindPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  final ItemKind value;
  final ValueChanged<ItemKind> onChanged;

  /// Changing the kind of an item that has already moved stock would leave the
  /// ledger describing something that no longer exists, so it is fixed once the
  /// item has history.
  final bool locked;

  static IconData iconFor(ItemKind kind) => switch (kind) {
        ItemKind.stock => Icons.inventory_2_outlined,
        ItemKind.service => Icons.handyman_outlined,
        ItemKind.bundle => Icons.widgets_outlined,
        ItemKind.group => Icons.category_outlined,
      };

  static Color colorFor(ItemKind kind) => switch (kind) {
        ItemKind.stock => AppColors.brand,
        ItemKind.service => AppColors.info,
        ItemKind.bundle => AppColors.tileTints[3],
        ItemKind.group => AppColors.tileTints[5],
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 520 ? 2 : 4;
        const double gap = 10;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final ItemKind kind in ItemKind.values)
              SizedBox(
                width: width,
                child: _KindCard(
                  kind: kind,
                  selected: kind == value,
                  enabled: !locked || kind == value,
                  onTap: () => onChanged(kind),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ItemKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = ItemKindPicker.colorFor(kind);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected
            ? tint.withValues(alpha: theme.isDark ? 0.20 : 0.10)
            : theme.surfaces.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? tint : theme.surfaces.hairline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(ItemKindPicker.iconFor(kind), size: 18, color: tint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr(kind.labelKey),
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, size: 16, color: tint),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(kind.hintKey),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
