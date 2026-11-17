import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../localization/app_text.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import '../theme/surfaces.dart';

/// How every form in the app is presented.
///
/// One call, two shapes: a centred dialog on a desktop till, a draggable sheet
/// on a phone. Screens do not decide which — they hand over a form and a title
/// and get the right thing for the window they are in, which is why the item
/// editor is one widget rather than a dialog and a page that drift apart.
Future<T?> showAppModal<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context) builder,
  String? subtitle,
  double width = 640,
  bool dismissible = true,
}) {
  if (Responsive.isMobile(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController controller) =>
            _ModalFrame(
          title: title,
          subtitle: subtitle,
          scrollController: controller,
          child: builder(context),
        ),
      ),
    );
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (BuildContext dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: _ModalFrame(
          title: title,
          subtitle: subtitle,
          child: builder(dialogContext),
        ),
      ),
    ),
  );
}

class _ModalFrame extends StatelessWidget {
  const _ModalFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.scrollController,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsetsDirectional.only(
            start: 22,
            end: 12,
            top: 16,
            bottom: 14,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.surfaces.hairline)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleLarge),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr(AppText.close),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The row of buttons at the bottom of a form, always in the same order.
class ModalActions extends StatelessWidget {
  const ModalActions({
    super.key,
    required this.onSave,
    this.saveLabel,
    this.busy = false,
    this.destructive,
    this.destructiveLabel,
  });

  final VoidCallback? onSave;
  final String? saveLabel;
  final bool busy;
  final VoidCallback? destructive;
  final String? destructiveLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (destructive != null)
          TextButton.icon(
            onPressed: busy ? null : destructive,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(destructiveLabel ?? context.tr(AppText.delete)),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        const Spacer(),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr(AppText.cancel)),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: busy ? null : onSave,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(saveLabel ?? context.tr(AppText.save)),
        ),
      ],
    );
  }
}

/// "Are you sure?" — with the consequence spelled out, not just the question.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = true,
  IconData icon = Icons.help_outline,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      icon: Icon(
        icon,
        color: destructive
            ? AppColors.danger
            : Theme.of(dialogContext).colorScheme.primary,
      ),
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.tr(AppText.cancel)),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel ?? dialogContext.tr(AppText.confirm)),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The standard delete confirmation, so the wording is the same everywhere.
Future<bool> confirmDelete(BuildContext context, {String? what}) => confirm(
      context,
      title: context.tr(AppText.confirmDelete),
      message: what == null
          ? context.tr(AppText.confirmDeleteMsg)
          : '$what\n\n${context.tr(AppText.confirmDeleteMsg)}',
      confirmLabel: context.tr(AppText.delete),
      icon: Icons.delete_outline,
    );
