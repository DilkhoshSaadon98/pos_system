import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/accounting_entities.dart';
import '../cubit/journal_cubit.dart';

/// A hand-written voucher.
///
/// The running difference at the bottom is the whole design: the Post button
/// stays disabled until it is zero, so an unbalanced entry is impossible to
/// submit rather than merely refused afterwards. `Journal.post` refuses one
/// anyway — this is the polite version of the same rule.
Future<void> showVoucherEditor(BuildContext context, JournalCubit cubit) =>
    showAppModal<void>(
      context,
      width: 760,
      title: context.tr(AppText.acctJournalNew),
      builder: (BuildContext modalContext) => BlocProvider<JournalCubit>.value(
        value: cubit,
        child: const _VoucherEditor(),
      ),
    );

class _VoucherEditor extends StatefulWidget {
  const _VoucherEditor();

  @override
  State<_VoucherEditor> createState() => _VoucherEditorState();
}

class _VoucherEditorState extends State<_VoucherEditor> {
  final TextEditingController _memo = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;

  List<VoucherLine> _lines = <VoucherLine>[
    const VoucherLine(),
    const VoucherLine(),
  ];

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  int get _debit =>
      _lines.fold(0, (int s, VoucherLine l) => s + l.debitMinor);

  int get _credit =>
      _lines.fold(0, (int s, VoucherLine l) => s + l.creditMinor);

  int get _difference => _debit - _credit;

  bool get _canPost =>
      _difference == 0 &&
      _debit > 0 &&
      _lines.where((VoucherLine l) => !l.isEmpty).length >= 2;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Account> accounts = context.read<JournalCubit>().state.accounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 220,
              child: DateField(
                label: context.tr(AppText.acctEntryDate),
                value: _date,
                onChanged: (DateTime? d) =>
                    setState(() => _date = d ?? _date),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                controller: _memo,
                label: context.tr(AppText.acctMemo),
                prefixIcon: Icons.notes_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.surfaces.hairline),
          ),
          child: Column(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.surfaces.raised,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Text(context.tr(AppText.acctAccount),
                          style: theme.textTheme.labelSmall),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        context.tr(AppText.acctDebit),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 130,
                      child: Text(
                        context.tr(AppText.acctCredit),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              for (int i = 0; i < _lines.length; i++) ...<Widget>[
                Divider(height: 1, color: theme.surfaces.hairline),
                _LineRow(
                  key: ValueKey<int>(i),
                  line: _lines[i],
                  accounts: accounts,
                  onChanged: (VoucherLine l) => setState(() => _lines[i] = l),
                  onRemove: _lines.length <= 2
                      ? null
                      : () => setState(() => _lines.removeAt(i)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () =>
                setState(() => _lines = <VoucherLine>[..._lines, const VoucherLine()]),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr(AppText.acctAddLine)),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (_difference == 0 ? AppColors.ok : AppColors.warning)
                .withValues(alpha: theme.isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                label: context.tr(AppText.acctDebit),
                value: Fmt.moneyMinor(_debit),
              ),
              TotalRow(
                label: context.tr(AppText.acctCredit),
                value: Fmt.moneyMinor(_credit),
              ),
              TotalRow(
                emphasis: true,
                label: context.tr(
                  _difference == 0 ? AppText.acctBalanced : AppText.acctDifference,
                ),
                value: Fmt.moneyMinor(_difference),
                color: _difference == 0 ? AppColors.ok : AppColors.danger,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ModalActions(
          busy: _busy,
          saveLabel: context.tr(AppText.acctPost),
          onSave: _canPost ? _post : null,
        ),
      ],
    );
  }

  Future<void> _post() async {
    setState(() => _busy = true);

    final bool ok = await context.read<JournalCubit>().postVoucher(
          lines: _lines,
          date: _date,
          memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
          userId: context.read<AuthCubit>().state.user?.id,
        );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      AppSnack.success(context, context.tr(AppText.acctPosted));
      Navigator.of(context).pop();
    } else {
      final String? detail = context.read<JournalCubit>().state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}

class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.accounts,
    required this.onChanged,
    this.onRemove,
  });

  final VoucherLine line;
  final List<Account> accounts;
  final ValueChanged<VoucherLine> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  final TextEditingController _debit = TextEditingController();
  final TextEditingController _credit = TextEditingController();

  @override
  void dispose() {
    _debit.dispose();
    _credit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<int>(
              initialValue: widget.line.accountId,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.tr(AppText.acctPickAccount),
                border: InputBorder.none,
              ),
              items: <DropdownMenuItem<int>>[
                for (final Account a in widget.accounts)
                  DropdownMenuItem<int>(
                    value: a.id,
                    child: Text(a.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (int? id) =>
                  widget.onChanged(widget.line.copyWith(accountId: id)),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _debit,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true),
              onChanged: (String v) {
                final Money? m = Fmt.parseMoney(v);
                // A line is a debit or a credit, never both. Typing in one
                // column empties the other, which is also what the CHECK
                // constraint on `journal_lines` insists on.
                if ((m?.minor ?? 0) > 0) _credit.clear();
                widget.onChanged(VoucherLine(
                  accountId: widget.line.accountId,
                  debitMinor: m?.minor ?? 0,
                  creditMinor: (m?.minor ?? 0) > 0 ? 0 : widget.line.creditMinor,
                  partyId: widget.line.partyId,
                  memo: widget.line.memo,
                ));
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _credit,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true),
              onChanged: (String v) {
                final Money? m = Fmt.parseMoney(v);
                if ((m?.minor ?? 0) > 0) _debit.clear();
                widget.onChanged(VoucherLine(
                  accountId: widget.line.accountId,
                  debitMinor: (m?.minor ?? 0) > 0 ? 0 : widget.line.debitMinor,
                  creditMinor: m?.minor ?? 0,
                  partyId: widget.line.partyId,
                  memo: widget.line.memo,
                ));
              },
            ),
          ),
          SizedBox(
            width: 40,
            child: widget.onRemove == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.danger,
                    onPressed: widget.onRemove,
                  ),
          ),
        ],
      ),
    );
  }
}
