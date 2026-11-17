import 'package:cashier_system_v2/core/classes/enums.dart';
import 'package:cashier_system_v2/core/localization/app_localizations.dart';
import 'package:cashier_system_v2/core/localization/app_text.dart';
import 'package:cashier_system_v2/features/pos/presentation/cubit/pos_cubit.dart';
import 'package:cashier_system_v2/features/pos/presentation/cubit/pos_state.dart';
import 'package:cashier_system_v2/features/pos/presentation/widgets/pos_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.state,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PosCubit cubit = context.read<PosCubit>();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      color: theme.cardColor,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: cubit.search,
              onSubmitted: (String value) {
                cubit.submitScan(value);
                controller.clear();
                focusNode.requestFocus();
              },
              decoration: InputDecoration(
                hintText: context.tr(AppText.posSearchHint),
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 21),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          cubit.clearSearch();
                          focusNode.requestFocus();
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _PriceModeToggle(state: state),
          const SizedBox(width: 6),
          _HeldButton(state: state),
        ],
      ),
    );
  }
}

class _PriceModeToggle extends StatelessWidget {
  const _PriceModeToggle({required this.state});

  final PosState state;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PriceMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: <ButtonSegment<PriceMode>>[
        for (final PriceMode m in PriceMode.values)
          ButtonSegment<PriceMode>(
            value: m,
            label: Text(
              context.tr(m.labelKey).split(' ').first,
            ),
          ),
      ],
      selected: <PriceMode>{state.priceMode},
      onSelectionChanged: (Set<PriceMode> s) =>
          context.read<PosCubit>().setPriceMode(s.first),
    );
  }
}

class _HeldButton extends StatelessWidget {
  const _HeldButton({required this.state});

  final PosState state;

  @override
  Widget build(BuildContext context) {
    final PosCubit cubit = context.read<PosCubit>();

    return Badge(
      isLabelVisible: state.heldCarts.isNotEmpty,
      label: Text('${state.heldCarts.length}'),
      child: IconButton.filledTonal(
        tooltip: context.tr(AppText.posHeldCarts),
        icon: const Icon(Icons.pause_circle_outline),
        onPressed: () async {
          final int? cartId = await showHeldCarts(
            context,
            carts: state.heldCarts,
            onDiscard: cubit.discardCart,
          );
          if (cartId != null) await cubit.resumeCart(cartId);
        },
      ),
    );
  }
}
