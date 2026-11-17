import 'package:cashier_system_v2/core/localization/app_localizations.dart';
import 'package:cashier_system_v2/core/localization/app_text.dart';
import 'package:cashier_system_v2/core/theme/surfaces.dart';
import 'package:flutter/material.dart';

class PosShortcutBar extends StatelessWidget {
  const PosShortcutBar({super.key});

  static const List<List<String>> _keys = <List<String>>[
    <String>['F2', AppText.posShortcutSearch],
    <String>['F3', AppText.posShortcutCustomer],
    <String>['F4', AppText.posShortcutHold],
    <String>['F5', AppText.posShortcutHeld],
    <String>['F6', AppText.posShortcutPriceMode],
    <String>['F7', AppText.posShortcutLine],
    <String>['F8', AppText.posShortcutClear],
    <String>['F9', AppText.posShortcutReprint],
    <String>['F12', AppText.posShortcutPay],
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        border: Border(top: BorderSide(color: theme.surfaces.hairline)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: <Widget>[
          for (final List<String> pair in _keys)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.surfaces.hairline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    pair[0],
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  context.tr(pair[1]),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.surfaces.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
