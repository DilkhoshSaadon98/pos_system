import 'package:flutter/material.dart';

import '../theme/surfaces.dart';

/// A keypad for a till.
///
/// Touch screens on counters are not phones: they are far away, often greasy,
/// and used by somebody who is also holding a bag. The keys are deliberately
/// large, there is no long-press behaviour, and the only destructive key sits
/// away from the digits.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.onDecimal,
    this.allowDecimal = true,
    this.extra,
  });

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback? onDecimal;

  /// Pieces cannot be sold in halves; kilograms can. The item's base unit
  /// decides, so the key is simply absent when it would produce a quantity the
  /// stock ledger cannot represent honestly.
  final bool allowDecimal;

  /// An extra key on the bottom row — "×10", "00", a currency shortcut.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final List<String> row in const <List<String>>[
          <String>['7', '8', '9'],
          <String>['4', '5', '6'],
          <String>['1', '2', '3'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                for (final String digit in row) ...<Widget>[
                  Expanded(
                    child: _Key(
                      label: digit,
                      onTap: () => onDigit(digit),
                    ),
                  ),
                  if (digit != row.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: allowDecimal
                  ? _Key(label: '.', onTap: onDecimal ?? () => onDigit('.'))
                  : (extra ?? _Key(label: '00', onTap: () => onDigit('00'))),
            ),
            const SizedBox(width: 8),
            Expanded(child: _Key(label: '0', onTap: () => onDigit('0'))),
            const SizedBox(width: 8),
            Expanded(
              child: _Key(
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
                onLongPress: onClear,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap, this.onLongPress});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.surfaces.raised,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 52,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 21)
                : Text(
                    label ?? '',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Holds what the keypad is typing, so a screen does not have to.
class PadBuffer {
  PadBuffer([this.text = '']);

  String text;

  void digit(String d) {
    if (d == '.' && text.contains('.')) return;
    if (d == '.' && text.isEmpty) {
      text = '0.';
      return;
    }
    if (text == '0' && d != '.') {
      text = d;
      return;
    }
    text += d;
  }

  void backspace() {
    if (text.isEmpty) return;
    text = text.substring(0, text.length - 1);
  }

  void clear() => text = '';

  bool get isEmpty => text.isEmpty;
}
