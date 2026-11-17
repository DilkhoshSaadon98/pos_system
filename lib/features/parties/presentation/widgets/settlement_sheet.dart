import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/accounting/account_keys.dart';
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
import '../../domain/entities/party.dart';
import '../cubit/parties_cubit.dart';

/// Taking money in from a customer, or paying it out to a supplier.
///
/// The unpaid invoices are shown because that is the question behind the
/// question: a customer handing over money usually means "for the ones from
/// last week". The default is oldest first, which is what every shop does and
/// what keeps an ageing report meaningful.
Future<void> showSettlement(
  BuildContext context,
  PartiesCubit cubit,
  Party party,
) =>
    showAppModal<void>(
      context,
      width: 520,
      title: context.tr(cubit.state.isCustomers
          ? AppText.partiesReceipt
          : AppText.partiesPayment),
      subtitle: party.name,
      builder: (BuildContext context) =>
          _Settlement(cubit: cubit, party: party),
    );

class _Settlement extends StatefulWidget {
  const _Settlement({required this.cubit, required this.party});

  final PartiesCubit cubit;
  final Party party;

  @override
  State<_Settlement> createState() => _SettlementState();
}

class _SettlementState extends State<_Settlement> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  final TextEditingController _reference = TextEditingController();

  String _method = AccountKeys.cash;
  bool _oldestFirst = true;
  bool _busy = true;
  List<OpenDocument> _open = const <OpenDocument>[];

  @override
  void initState() {
    super.initState();
    _loadOpen();
  }

  Future<void> _loadOpen() async {
    final List<OpenDocument> open =
        await widget.cubit.openDocuments(widget.party.id);
    if (!mounted) return;
    setState(() {
      _open = open;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Money get _outstanding => widget.party.balance.abs;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool receipt = widget.cubit.state.isCustomers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                emphasis: true,
                label: context.tr(
                    receipt ? AppText.partiesOwesUs : AppText.partiesWeOwe),
                value: Fmt.money(_outstanding),
                color: receipt ? AppColors.warning : AppColors.info,
              ),
              if (!widget.party.creditLimit.isZero)
                TotalRow(
                  label: context.tr(AppText.partiesCreditLimit),
                  value: Fmt.money(widget.party.creditLimit),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MoneyField(
          controller: _amount,
          autofocus: true,
          label: context.tr(AppText.amount),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ActionChip(
              label: Text(context.tr(AppText.all)),
              onPressed: () => setState(
                () => _amount.text = Fmt.moneyPlain(_outstanding.minor),
              ),
            ),
            for (final OpenDocument d in _open.take(3))
              ActionChip(
                label: Text('${d.number}  ·  ${Fmt.money(d.due)}'),
                onPressed: () => setState(
                  () => _amount.text = Fmt.moneyPlain(d.due.minor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AppDropdown<String>(
          label: context.tr(AppText.method),
          value: _method,
          items: const <String>[
            AccountKeys.cash,
            AccountKeys.bank,
            AccountKeys.card,
          ],
          itemLabel: (String key) => context.tr(switch (key) {
            AccountKeys.bank => AppText.bank,
            AccountKeys.card => AppText.card,
            _ => AppText.cash,
          }),
          onChanged: (String? v) => setState(() => _method = v ?? _method),
        ),
        const SizedBox(height: 14),
        MoneyField(
          controller: _discount,
          label: context.tr(AppText.partiesDiscountGiven),
          helper: context.tr(AppText.optional),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _reference,
          label: context.tr(AppText.reference),
        ),
        const SizedBox(height: 6),
        AppSwitchTile(
          icon: Icons.low_priority,
          title: context.tr(AppText.partiesAllocate),
          subtitle: context.tr(AppText.partiesOpenDocuments),
          value: _oldestFirst,
          onChanged: (bool v) => setState(() => _oldestFirst = v),
        ),
        if (_open.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.surfaces.hairline),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _open.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: 1, color: theme.surfaces.hairline),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${_open[i].number}  ·  ${Fmt.date(_open[i].issuedAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          Fmt.money(_open[i].due),
                          style: theme.textTheme.bodyMedium
                              ?.merge(theme.tabular),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        ModalActions(
          busy: _busy,
          saveLabel: context.tr(AppText.partiesSettle),
          onSave: (MoneyField.read(_amount)?.isPositive ?? false)
              ? _save
              : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);

    final bool ok = await widget.cubit.settle(
      partyId: widget.party.id,
      amount: MoneyField.read(_amount) ?? Money.zero,
      methodKey: _method,
      discount: MoneyField.read(_discount) ?? Money.zero,
      userId: context.read<AuthCubit>().state.user?.id,
      reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      allocateOldestFirst: _oldestFirst,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      AppSnack.success(context, context.tr(AppText.partiesSettled));
      Navigator.of(context).pop();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}
