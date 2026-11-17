import 'package:cashier_system_v2/core/localization/app_localizations.dart';
import 'package:cashier_system_v2/core/localization/app_text.dart';
import 'package:cashier_system_v2/features/catalog/domain/entities/catalog_entities.dart';
import 'package:cashier_system_v2/features/pos/presentation/cubit/pos_cubit.dart';
import 'package:cashier_system_v2/features/pos/presentation/cubit/pos_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CategoryStrip extends StatelessWidget {
  const CategoryStrip({super.key, required this.state});

  final PosState state;

  @override
  Widget build(BuildContext context) {
    if (state.categories.isEmpty) return const SizedBox(height: 6);
    final PosCubit cubit = context.read<PosCubit>();

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(context.tr(AppText.all)),
                selected: state.categoryId == null,
                onSelected: (_) => cubit.selectCategory(null),
              ),
            ),
            for (final Category c in state.categories)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: state.categoryId == c.id,
                  onSelected: (_) => cubit.selectCategory(c.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
