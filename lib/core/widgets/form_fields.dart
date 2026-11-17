import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/discount.dart';
import '../format/formatters.dart';
import '../localization/app_localizations.dart';
import '../localization/app_text.dart';
import '../money/money.dart';
import '../theme/surfaces.dart';

/// The inputs every form in the app is built out of.
///
/// The point of putting them here is not to save typing — it is that a money
/// field must never hand back a double. [MoneyField] parses what was typed into
/// [Money] (minor units) exactly once, at the edge; nothing downstream ever
/// sees the string or a floating point number.

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffix,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.obscure = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final bool obscure;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textAlign: textAlign,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

/// A field that reads and writes [Money].
///
/// Typing is free-form — `1,250`, `1 250`, `١٢٥٠` all work, because a cashier
/// types what is on the price tag. The value only becomes a number when it is
/// read, and an unparseable string reads as `null` rather than as zero, so a
/// half-typed price never silently becomes free.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.helper,
    this.allowNegative = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<Money?>? onChanged;
  final ValueChanged<Money?>? onSubmitted;
  final FocusNode? focusNode;
  final String? helper;
  final bool allowNegative;
  final TextInputAction? textInputAction;

  static Money? read(TextEditingController c) => Fmt.parseMoney(c.text);

  static void write(TextEditingController c, Money value) =>
      c.text = Fmt.money(value, withSymbol: false);

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      focusNode: focusNode,
      label: label,
      helper: helper,
      enabled: enabled,
      autofocus: autofocus,
      textAlign: TextAlign.end,
      textInputAction: textInputAction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          RegExp(allowNegative ? r'[0-9.,\-٠-٩٫ ]' : r'[0-9.,٠-٩٫ ]'),
        ),
      ],
      suffix: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12, start: 4),
        child: Text(
          Fmt.instance.currencySymbol,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      onChanged: onChanged == null
          ? null
          : (String v) => onChanged!(Fmt.parseMoney(v)),
      onSubmitted: onSubmitted == null
          ? null
          : (String v) => onSubmitted!(Fmt.parseMoney(v)),
      validator: (String? v) {
        if ((v ?? '').trim().isEmpty) return null;
        return Fmt.parseMoney(v!) == null
            ? context.tr(AppText.invalidNumber)
            : null;
      },
    );
  }
}

/// A field that reads and writes [Qty] — thousandths of a unit.
class QtyField extends StatelessWidget {
  const QtyField({
    super.key,
    required this.controller,
    required this.label,
    this.unitName,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? unitName;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<Qty?>? onChanged;
  final ValueChanged<Qty?>? onSubmitted;
  final FocusNode? focusNode;
  final String? helper;

  static Qty? read(TextEditingController c) => Fmt.parseQty(c.text);

  static void write(TextEditingController c, Qty value) =>
      c.text = Fmt.qty(value);

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      focusNode: focusNode,
      label: label,
      helper: helper,
      enabled: enabled,
      autofocus: autofocus,
      textAlign: TextAlign.end,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٠-٩٫ ]')),
      ],
      suffix: unitName == null
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.only(end: 12, start: 4),
              child: Text(
                unitName!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      onChanged:
          onChanged == null ? null : (String v) => onChanged!(Fmt.parseQty(v)),
      onSubmitted: onSubmitted == null
          ? null
          : (String v) => onSubmitted!(Fmt.parseQty(v)),
      validator: (String? v) {
        if ((v ?? '').trim().isEmpty) return null;
        return Fmt.parseQty(v!) == null
            ? context.tr(AppText.invalidNumber)
            : null;
      },
    );
  }
}

/// A percentage, held as basis points. `7.5` in the box is `750` in the model.
class PercentField extends StatelessWidget {
  const PercentField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<int?>? onChanged;
  final String? helper;

  static int? read(TextEditingController c) => Fmt.parsePercentBp(c.text);

  static void write(TextEditingController c, int bp) =>
      c.text = bp == 0 ? '' : (bp / 100).toString();

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      helper: helper,
      enabled: enabled,
      textAlign: TextAlign.end,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٠-٩٫]')),
      ],
      suffix: const Padding(
        padding: EdgeInsetsDirectional.only(end: 12, start: 4),
        child: Text('%'),
      ),
      onChanged: onChanged == null
          ? null
          : (String v) => onChanged!(Fmt.parsePercentBp(v)),
    );
  }
}

/// Percentage-or-amount, the shape every discount in this app takes.
///
/// Keeping the two apart until the moment of calculation is what lets a bill
/// discount stay a percentage when a line changes, instead of being frozen into
/// a stale amount — the bug that made the old cart totals disagree with the
/// printed receipt.
class DiscountField extends StatefulWidget {
  const DiscountField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final DiscountSpec value;
  final ValueChanged<DiscountSpec> onChanged;
  final String? label;
  final bool enabled;

  @override
  State<DiscountField> createState() => _DiscountFieldState();
}

class _DiscountFieldState extends State<DiscountField> {
  late final TextEditingController _controller = TextEditingController(
    text: _textFor(widget.value),
  );
  late DiscountKind _kind =
      widget.value.kind == DiscountKind.none ? DiscountKind.percent : widget.value.kind;

  static String _textFor(DiscountSpec spec) => switch (spec.kind) {
        DiscountKind.none => '',
        DiscountKind.percent => spec.value == 0 ? '' : '${spec.value / 100}',
        DiscountKind.amount => spec.value == 0 ? '' : Fmt.moneyPlain(spec.value),
      };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final String raw = _controller.text.trim();
    if (raw.isEmpty) {
      widget.onChanged(const DiscountSpec.none());
      return;
    }
    if (_kind == DiscountKind.percent) {
      final int? bp = Fmt.parsePercentBp(raw);
      widget.onChanged(
        bp == null ? const DiscountSpec.none() : DiscountSpec.percentBp(bp),
      );
    } else {
      final Money? money = Fmt.parseMoney(raw);
      widget.onChanged(
        money == null
            ? const DiscountSpec.none()
            : DiscountSpec.amountMinor(money.minor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppTextField(
            controller: _controller,
            label: widget.label ?? context.tr(AppText.discount),
            enabled: widget.enabled,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٠-٩٫ ]')),
            ],
            onChanged: (_) => _emit(),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<DiscountKind>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: <ButtonSegment<DiscountKind>>[
            const ButtonSegment<DiscountKind>(
              value: DiscountKind.percent,
              label: Text('%'),
            ),
            ButtonSegment<DiscountKind>(
              value: DiscountKind.amount,
              label: Text(Fmt.instance.currencySymbol),
            ),
          ],
          selected: <DiscountKind>{_kind},
          onSelectionChanged: widget.enabled
              ? (Set<DiscountKind> s) {
                  setState(() => _kind = s.first);
                  _emit();
                }
              : null,
        ),
      ],
    );
  }
}

/// A dropdown that looks like the rest of the fields rather than like a button.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
    this.itemLabel,
    this.enabled = true,
    this.helper,
    this.prefixIcon,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String label;
  final String Function(T item)? itemLabel;
  final bool enabled;
  final String? helper;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
      ),
      items: <DropdownMenuItem<T>>[
        for (final T item in items)
          DropdownMenuItem<T>(
            value: item,
            child: Text(
              itemLabel?.call(item) ?? '$item',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// A switch with a title and an explanation — the shape of every setting.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.bodySmall),
      secondary: icon == null
          ? null
          : Icon(icon, color: theme.surfaces.muted, size: 20),
    );
  }
}

/// A date, picked or typed, always stored as `yyyy-MM-dd`.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.clearable = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final DateTime now = DateTime.now();
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(now.year - 5),
          lastDate: lastDate ?? DateTime(now.year + 5),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
          suffixIcon: clearable && value != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(
          value == null ? '—' : Fmt.date(value!.toIso8601String()),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
