import 'package:cashier_system_v2/core/format/formatters.dart';
import 'package:cashier_system_v2/core/localization/app_localizations.dart';
import 'package:cashier_system_v2/core/localization/app_text.dart';
import 'package:cashier_system_v2/core/theme/surfaces.dart';
import 'package:cashier_system_v2/features/pos/presentation/cubit/pos_state.dart';
import 'package:flutter/material.dart';

class PosMobileCartBar extends StatelessWidget {
  const PosMobileCartBar({super.key, required this.state, required this.onOpen});

  final PosState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed:
                state.lines.isEmpty || state.blockedByShift ? null : onOpen,
            child: Row(
              children: <Widget>[
                Badge(
                  isLabelVisible: state.lines.isNotEmpty,
                  label: Text('${state.lines.length}'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    state.blockedByShift
                        ? context.tr(AppText.shiftNone)
                        : (state.lines.isEmpty
                            ? context.tr(AppText.posCartEmpty)
                            : context.tr(AppText.posPay)),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  Fmt.moneyMinor(state.totals.totalMinor),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: Colors.white)
                      .merge(theme.tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

