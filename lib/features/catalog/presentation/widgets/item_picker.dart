import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/catalog_entities.dart';

/// "Which item?" — the same picker for a bundle part, a purchase line and a
/// stock count, so the search behaves identically everywhere.
///
/// It searches as you type, with the same debounce as the item list, and it
/// takes a barcode: scanning into this box is the fastest way to add a line.
Future<Item?> showItemPicker(
  BuildContext context, {
  required Future<List<Item>> Function(String text) search,
  String title = AppText.item,
  String? hint,
}) =>
    showAppModal<Item>(
      context,
      title: context.tr(title),
      width: 560,
      builder: (BuildContext context) => _ItemPickerBody(
        search: search,
        hint: hint,
      ),
    );

class _ItemPickerBody extends StatefulWidget {
  const _ItemPickerBody({required this.search, this.hint});

  final Future<List<Item>> Function(String text) search;
  final String? hint;

  @override
  State<_ItemPickerBody> createState() => _ItemPickerBodyState();
}

class _ItemPickerBodyState extends State<_ItemPickerBody> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Item> _results = const <Item>[];
  bool _loading = true;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String text) async {
    final int token = ++_token;
    setState(() => _loading = true);
    final List<Item> found = await widget.search(text);
    if (!mounted || token != _token) return;
    setState(() {
      _results = found;
      _loading = false;
    });
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _run(text));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: (String v) {
            // A scanner ends with Enter. One result means it hit.
            if (_results.length == 1) Navigator.of(context).pop(_results.first);
          },
          decoration: InputDecoration(
            hintText: widget.hint ?? context.tr(AppText.posSearchHint),
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 340,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      message: context.tr(AppText.noResults),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: theme.surfaces.hairline),
                      itemBuilder: (BuildContext context, int index) {
                        final Item item = _results[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.displayName),
                          subtitle: Text(
                            <String>[
                              if ((item.sku ?? '').isNotEmpty) item.sku!,
                              if (item.categoryName != null)
                                item.categoryName!,
                              '${Fmt.qtyMilli(item.stockQtyMilli)} ${item.baseUnitName}',
                            ].join('  ·  '),
                          ),
                          trailing: Text(
                            Fmt.money(item.defaultSellPrice),
                            style: theme.textTheme.bodyMedium
                                ?.merge(theme.tabular),
                          ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
