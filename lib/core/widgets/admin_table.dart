import 'package:flutter/material.dart';

import '../theme/responsive.dart';
import '../theme/surfaces.dart';

/// One column of an [AdminTable].
class AdminColumn<T> {
  const AdminColumn({
    required this.label,
    required this.cell,
    this.flex = 3,
    this.alignEnd = false,
    this.hideBelow,
  });

  final String label;

  /// Builds the cell content for a given row value.
  final Widget Function(BuildContext context, T row) cell;
  final int flex;

  /// Money and quantities are read down the column, so they sit against the
  /// end edge — and "end", not "right", because the whole app flips in Arabic.
  final bool alignEnd;

  /// Drop this column when the table is narrower than this. Lets one table
  /// definition serve a 24" till and a laptop without a second layout.
  final double? hideBelow;
}

/// A styled, responsive data table.
///
/// Desktop and tablet get a real column layout; below the mobile breakpoint
/// each record collapses into the card supplied by [mobileCard], which keeps
/// every field readable without horizontal scrolling. The old project solved
/// this by shipping a `windows/` screen and a `mobile/` screen per feature —
/// two files that slowly stopped agreeing with each other.
class AdminTable<T> extends StatelessWidget {
  const AdminTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.mobileCard,
    this.empty,
    this.onRowTap,
    this.rowTint,
    this.footer,
  });

  final List<T> rows;
  final List<AdminColumn<T>> columns;
  final Widget Function(BuildContext context, T row) mobileCard;
  final Widget? empty;
  final void Function(T row)? onRowTap;

  /// A wash behind a whole row — a voided invoice, a negative balance.
  final Color? Function(BuildContext context, T row)? rowTint;

  /// A totals strip pinned under the last row.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && empty != null) return Card(child: empty!);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < Responsive.mobileMax) {
          return Column(
            children: <Widget>[
              for (final T row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: mobileCard(context, row),
                ),
              if (footer != null) Card(child: footer!),
            ],
          );
        }
        return Card(child: _wide(context, constraints.maxWidth));
      },
    );
  }

  Widget _wide(BuildContext context, double width) {
    final ThemeData theme = Theme.of(context);
    final List<AdminColumn<T>> visible = columns
        .where((AdminColumn<T> c) => c.hideBelow == null || width >= c.hideBelow!)
        .toList(growable: false);

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            border: Border(bottom: BorderSide(color: theme.surfaces.hairline)),
          ),
          child: Row(
            children: <Widget>[
              for (final AdminColumn<T> column in visible)
                Expanded(
                  flex: column.flex,
                  child: Align(
                    alignment: column.alignEnd
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Text(
                      column.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: theme.surfaces.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) Divider(height: 1, color: theme.surfaces.hairline),
          _HoverRow(
            onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
            tint: rowTint?.call(context, rows[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: <Widget>[
                  for (final AdminColumn<T> column in visible)
                    Expanded(
                      flex: column.flex,
                      child: Align(
                        alignment: column.alignEnd
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        child: column.cell(context, rows[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (footer != null) ...<Widget>[
          Divider(height: 1, color: theme.surfaces.hairline),
          Container(
            color: theme.surfaces.raised,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: footer!,
          ),
        ],
      ],
    );
  }
}

/// A table row that lifts slightly under the cursor.
///
/// Scanning a wide table is much easier when the row under the pointer is
/// picked out — on a dense list it is the difference between reading across
/// and losing your place halfway.
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap, this.tint});

  final Widget child;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: _hover
              ? theme.surfaces.overlay
              : (widget.tint ?? Colors.transparent),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Container used for the mobile variant of a table row.
class AdminRecordCard extends StatelessWidget {
  const AdminRecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.details = const <Widget>[],
    this.actions = const <Widget>[],
    this.leading,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final List<Widget> details;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.titleSmall),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (details.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 10, children: details),
              ],
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "label / value" pair used inside [AdminRecordCard].
class RecordDetail extends StatelessWidget {
  const RecordDetail({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.surfaces.muted,
            fontSize: 10.5,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600)
              .merge(theme.tabular),
        ),
      ],
    );
  }
}
