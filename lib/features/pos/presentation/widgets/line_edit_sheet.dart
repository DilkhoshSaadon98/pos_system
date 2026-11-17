import 'package:flutter/material.dart';

import '../../../../core/calc/discount.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/number_pad.dart';
import '../../../../core/widgets/panels.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../domain/entities/pos_line.dart';
import '../cubit/pos_cubit.dart';

Future<void> showLineEditor(
  BuildContext context,
  PosCubit cubit,
  int index,
  PosLine line,
) =>
    showAppModal<void>(
      context,
      width: 460,
      title: line.item.displayName,
      subtitle: line.item.categoryName,
      builder: (BuildContext context) => _LineEditor(
        cubit: cubit,
        index: index,
        line: line,
      ),
    );

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.cubit,
    required this.index,
    required this.line,
  });

  final PosCubit cubit;
  final int index;
  final PosLine line;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final PadBuffer _pad = PadBuffer(Fmt.qty(widget.line.qty));
  late final TextEditingController _price = TextEditingController(
    text: Fmt.moneyPlain(widget.line.unitPrice.minor),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.line.note ?? '');

  late ItemUnit _unit = widget.line.unit;
  late DiscountSpec _discount = widget.line.discount;
  late bool _gift = widget.line.isGift;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Qty get _qty => Fmt.parseQty(_pad.text) ?? widget.line.qty;

  bool get _allowsFraction =>
      widget.line.item.isWeighed || _unit.factorMilli != 1000;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Money price = Fmt.parseMoney(_price.text) ?? widget.line.unitPrice;
    final int gross = (price.minor * _qty.milli) ~/ 1000;
    final int discount = _discount.amountFor(gross);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---- quantity, big and unmistakable ---------------------------------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Text(
                context.tr(AppText.qty),
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                _pad.text.isEmpty ? '0' : _pad.text,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)
                    .merge(theme.tabular),
              ),
              const SizedBox(width: 8),
              Text(_unit.unitName, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NumberPad(
          allowDecimal: _allowsFraction,
          onDigit: (String d) => setState(() => _pad.digit(d)),
          onBackspace: () => setState(_pad.backspace),
          onClear: () => setState(_pad.clear),
        ),
        const SizedBox(height: 18),

        // ---- unit -----------------------------------------------------------
        if (widget.line.item.units.length > 1) ...<Widget>[
          Text(context.tr(AppText.posChooseUnit),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ItemUnit u in widget.line.item.units)
                ChoiceChip(
                  label: Text(
                    '${u.unitName}  ·  ${Fmt.money(u.priceFor(widget.cubit.state.priceMode))}',
                  ),
                  selected: u.id == _unit.id,
                  onSelected: (_) => setState(() {
                    _unit = u;
                    _price.text = Fmt.moneyPlain(
                      u.priceFor(widget.cubit.state.priceMode).minor,
                    );
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ---- price and discount ---------------------------------------------
        MoneyField(
          controller: _price,
          label: context.tr(AppText.price),
          helper: _unit.minPrice.isPositive
              ? '${context.tr(AppText.itemsMinPrice)}: ${Fmt.money(_unit.minPrice)}'
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        DiscountField(
          value: _discount,
          label: context.tr(AppText.posLineDiscount),
          onChanged: (DiscountSpec d) => setState(() => _discount = d),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: context.tr(AppText.posNoteHint),
        ),
        const SizedBox(height: 10),
        AppSwitchTile(
          icon: Icons.card_giftcard_outlined,
          title: context.tr(AppText.posGift),
          value: _gift,
          onChanged: (bool v) => setState(() => _gift = v),
        ),

        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                label: context.tr(AppText.gross),
                value: Fmt.moneyMinor(gross),
              ),
              if (discount > 0)
                TotalRow(
                  label: context.tr(AppText.discount),
                  value: '−${Fmt.moneyMinor(discount)}',
                  color: AppColors.warning,
                ),
              TotalRow(
                emphasis: true,
                label: context.tr(AppText.total),
                value: Fmt.moneyMinor(_gift ? 0 : gross - discount),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ModalActions(
          destructive: () {
            widget.cubit.removeLine(widget.index);
            Navigator.of(context).pop();
          },
          destructiveLabel: context.tr(AppText.remove),
          onSave: _apply,
        ),
      ],
    );
  }

  void _apply() {
    final PosCubit cubit = widget.cubit;

    if (_unit.id != widget.line.unit.id) cubit.changeUnit(widget.index, _unit);

    final Money? price = Fmt.parseMoney(_price.text);
    if (price != null && price != widget.line.unitPrice) {
      if (!cubit.setPrice(widget.index, price)) return;
    }

    cubit.setQty(widget.index, _qty);
    cubit.setLineDiscount(widget.index, _discount);
    cubit.setLineNote(
      widget.index,
      _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (_gift != widget.line.isGift) cubit.toggleGift(widget.index);

    Navigator.of(context).pop();
  }
}
