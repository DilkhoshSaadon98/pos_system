import 'package:flutter/material.dart';

import '../error/failures.dart';
import '../localization/app_localizations.dart';
import '../localization/app_text.dart';
import '../theme/app_colors.dart';
import '../theme/surfaces.dart';

/// The title block that opens every screen and every section inside one.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!dense)
              Container(
                width: 3,
                height: 22,
                margin: const EdgeInsetsDirectional.only(end: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Flexible(
              child: Text(
                title,
                style: dense
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 5),
          Padding(
            padding: EdgeInsetsDirectional.only(start: dense ? 0 : 15),
            child: Text(subtitle!, style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return titleBlock;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Stack the actions under the title when there is no room beside them.
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              titleBlock,
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    );
  }
}

/// Small pill used for statuses, stock levels and document kinds.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.compact = false,
  });

  factory StatusChip.neutral(
    BuildContext context,
    String label, {
    IconData? icon,
  }) =>
      StatusChip(
        label: label,
        color: Theme.of(context).surfaces.muted,
        icon: icon,
      );

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid rather than tinted — for the one status on a row that matters most.
  final bool filled;
  final bool compact;

  static const Color ok = AppColors.ok;
  static const Color warning = AppColors.warning;
  static const Color danger = AppColors.danger;
  static const Color info = AppColors.info;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.isDark;

    final Color background =
        filled ? color : color.withValues(alpha: isDark ? 0.20 : 0.13);
    final Color foreground = filled
        ? Colors.white
        : AppColors.readableOnTint(color, theme.brightness);

    return Container(
      padding: EdgeInsetsDirectional.only(
        start: icon == null ? (compact ? 8 : 10) : 7,
        end: compact ? 8 : 10,
        top: compact ? 3 : 4.5,
        bottom: compact ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: compact ? 12 : 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a list shows when there is genuinely nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.hint,
  });

  final String message;
  final IconData icon;
  final Widget? action;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.surfaces.raised,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: theme.surfaces.muted),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// What a screen shows instead of its content when the load failed.
///
/// Always with a retry button: nine failures out of ten in a local database are
/// a locked file or a busy moment, and the cure is to ask again.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              switch (failure) {
                ValidationFailure() => Icons.rule_folder_outlined,
                NotFoundFailure() => Icons.search_off,
                ConflictFailure() => Icons.block_outlined,
                PermissionFailure() => Icons.lock_outline,
                _ => Icons.error_outline,
              },
              color: AppColors.danger,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr(AppText.somethingWentWrong),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(failure.detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.tr(AppText.retry)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single figure with a label — the tiles across the top of the dashboard.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tint,
    this.footnote,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tint;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = tint ?? theme.colorScheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: theme.isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)
                      .merge(theme.tabular),
                ),
              ),
              if (footnote != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(footnote!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of `label ────── value`, the shape every totals panel is made of.
class TotalRow extends StatelessWidget {
  const TotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? labelStyle = emphasis
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium?.copyWith(color: theme.surfaces.muted);
    final TextStyle? valueStyle = (emphasis
            ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)
            : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))
        ?.copyWith(color: color)
        .merge(theme.tabular);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: emphasis ? 6 : 3),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: theme.surfaces.muted),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
