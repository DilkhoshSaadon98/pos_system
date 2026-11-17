import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../../core/widgets/stored_image.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../cubit/items_cubit.dart';

/// Categories, edited in place.
///
/// A list where every row is the form, rather than a list that opens a form:
/// there are only three fields, and a shop setting itself up adds ten of these
/// in a row.
Future<void> showCategoryManager(BuildContext context, ItemsCubit cubit) =>
    showAppModal<void>(
      context,
      width: 520,
      title: context.tr(AppText.itemsCategories),
      builder: (BuildContext context) => _CategoryManager(cubit: cubit),
    );

class _CategoryManager extends StatefulWidget {
  const _CategoryManager({required this.cubit});

  final ItemsCubit cubit;

  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  final TextEditingController _newName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final String name = _newName.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final bool ok = await widget.cubit
        .saveCategory(CategorySaveRequest(name: name));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _newName.clear();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Category> categories = widget.cubit.state.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: _newName,
                label: context.tr(AppText.name),
                autofocus: true,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr(AppText.add)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (categories.isEmpty)
          EmptyState(
            icon: Icons.folder_outlined,
            message: context.tr(AppText.nothingYet),
          )
        else
          for (final Category c in categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsetsDirectional.only(
                    start: 14, end: 6, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.surfaces.hairline),
                ),
                child: Row(
                  children: <Widget>[
                    // Picking a picture here saves at once. A category row is
                    // not a form with a Save button, so there is no other
                    // moment for the choice to be kept.
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: ImagePickerField(
                        name: c.imagePath,
                        size: 40,
                        prefix: 'cat',
                        icon: Icons.folder_outlined,
                        onChanged: (String? name) => _setImage(c, name),
                      ),
                    ),
                    Expanded(
                      child: Text(c.name, style: theme.textTheme.bodyMedium),
                    ),
                    StatusChip.neutral(
                      context,
                      '${c.itemCount} ${context.tr(AppText.items).toLowerCase()}',
                    ),
                    IconButton(
                      tooltip: context.tr(AppText.edit),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => _rename(c),
                    ),
                    IconButton(
                      tooltip: context.tr(AppText.delete),
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: AppColors.danger,
                      onPressed: () async {
                        if (!await confirmDelete(context, what: c.name)) return;
                        final bool ok = await widget.cubit.removeCategory(c.id);
                        if (!mounted) return;
                        if (!ok) {
                          final String? detail =
                              widget.cubit.state.failure?.detail;
                          if (detail != null) AppSnack.error(context, detail);
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _rename(Category category) async {
    final TextEditingController controller =
        TextEditingController(text: category.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.tr(AppText.edit)),
        content: AppTextField(
          controller: controller,
          autofocus: true,
          label: dialogContext.tr(AppText.name),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.tr(AppText.cancel)),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(dialogContext.tr(AppText.save)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    await widget.cubit.saveCategory(_request(category, name: name));
    if (mounted) setState(() {});
  }

  Future<void> _setImage(Category category, String? name) async {
    final bool ok = await widget.cubit.saveCategory(
      _request(category, imagePath: name, clearImage: name == null),
    );
    if (!mounted) return;
    if (!ok) {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
    setState(() {});
  }

  /// Everything the category already is, with one field changed.
  ///
  /// Written out because `saveCategory` replaces the row: renaming a category
  /// used to blank its colour, which nobody notices until the till strip turns
  /// grey a week later.
  CategorySaveRequest _request(
    Category category, {
    String? name,
    String? imagePath,
    bool clearImage = false,
  }) =>
      CategorySaveRequest(
        id: category.id,
        name: name ?? category.name,
        parentId: category.parentId,
        imagePath: clearImage ? null : (imagePath ?? category.imagePath),
        color: category.color,
        sortOrder: category.sortOrder,
        isActive: category.isActive,
      );
}
