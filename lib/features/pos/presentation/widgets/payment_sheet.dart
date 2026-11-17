import 'package:flutter/material.dart';

import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/fx.dart';
import '../../../../core/money/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/number_pad.dart';
import '../../../../core/widgets/panels.dart';
import '../cubit/pos_state.dart';

Future<List<TenderInput>?> showPaymentSheet(
  BuildContext context,
  PosState state, {
  ValueChanged<int>? onPointsChosen,
}) =>
    showAppModal<List<TenderInput>>(
      context,
      width: 560,
      title: context.tr(AppText.posPay),
      subtitle: state.customer?.name ?? context.tr(AppText.posWalkIn),
      builder: (BuildContext context) =>
          _PaymentBody(state: state, onPointsChosen: onPointsChosen),
    );

class _PaymentBody extends StatefulWidget {
  const _PaymentBody({required this.state, this.onPointsChosen});

  final PosState state;
  final ValueChanged<int>? onPointsChosen;

  @override
  State<_PaymentBody> createState() => _PaymentBodyState();
}

class _PaymentBodyState extends State<_PaymentBody> {
  final PadBuffer _pad = PadBuffer();
  TenderMethod _method = TenderMethod.cash;
  bool _foreign = false;

  int _points = 0;
  final List<TenderInput> _tenders = <TenderInput>[];

  int get _totalMinor => widget.state.totals.totalMinor;

  int get _tenderedMinor =>
      _tenders.fold(0, (int sum, TenderInput t) => sum + t.amountMinor);

  FxRate get _fx => widget.state.fx;
  int get _typedRaw => Fmt.parseMoney(_pad.text)?.minor ?? 0;
  int get _typedMinor => _foreign ? _fx.toBase(_typedRaw) : _typedRaw;

  TenderInput get _typedTender => _foreign
      ? TenderInput(
          method: TenderMethod.cash,
          amountMinor: _typedMinor,
          currencyCode: _fx.code,
          fxRateMilli: _fx.rateMilli,
          amountFxMinor: _typedRaw,
        )
      : TenderInput(method: _method, amountMinor: _typedMinor);

  SaleTotals get _preview => widget.state.totalsWith(<TenderInput>[
        ..._tenders,
        if (_typedMinor > 0) _typedTender,
      ]);

  int get _outstanding {
    final int left = _totalMinor - _tenderedMinor - _typedMinor;
    return left < 0 ? 0 : left;
  }

  void _usePoints(int points) {
    if (points <= 0) return;
    final int value = widget.state.loyalty.valueOf(points);
    if (value <= 0) return;

    setState(() {
      _points = points;
      _tenders.add(TenderInput(
        method: TenderMethod.voucher,
        amountMinor: value,
        reference: 'points:$points',
      ));
    });
    widget.onPointsChosen?.call(points);
  }

  void _addTender() {
    if (_typedMinor <= 0) return;
    setState(() {
      _tenders.add(_typedTender);
      _pad.clear();
    });
  }

  void _quick(int minor) => setState(() {
        _pad.text = Fmt.moneyPlain(minor);
      });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SaleTotals preview = _preview;
    final bool needsCustomer =
        preview.dueMinor > 0 && widget.state.customer == null;
    final bool overLimit = preview.dueMinor > 0 &&
        widget.state.customer != null &&
        widget.state.customer!.wouldExceedLimit(Money(preview.dueMinor));

    final bool blockedByCredit = overLimit && widget.state.blockedByCreditLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        //? ---- the two numbers that matter ------------------------------------
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                emphasis: true,
                label: context.tr(AppText.total),
                value: Fmt.moneyMinor(_totalMinor),
              ),
              TotalRow(
                label: context.tr(AppText.posTenderTotal),
                value: Fmt.moneyMinor(_tenderedMinor + _typedMinor),
              ),
              Divider(height: 18, color: theme.surfaces.hairline),
              if (preview.changeMinor > 0)
                TotalRow(
                  emphasis: true,
                  label: context.tr(AppText.posChange),
                  value: Fmt.moneyMinor(preview.changeMinor),
                  color: AppColors.ok,
                )
              else
                TotalRow(
                  emphasis: true,
                  label: context.tr(AppText.posRemaining),
                  value: Fmt.moneyMinor(_outstanding),
                  color: _outstanding == 0 ? AppColors.ok : AppColors.warning,
                ),
              if (preview.creditMinor > 0)
                TotalRow(
                  label: context.tr(AppText.credit),
                  value: Fmt.moneyMinor(preview.creditMinor),
                  color: AppColors.info,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        //? ---- points, when this customer has any ------------------------------
        if (widget.state.canUsePoints && _points == 0) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => _usePoints(widget.state.redeemablePoints),
            icon: const Icon(Icons.card_giftcard, size: 18),
            label: Text(
              context.tr(AppText.loyaltyAvailable, params: <String, Object?>{
                'n': widget.state.pointsBalance,
                'amount': Fmt.moneyMinor(
                  widget.state.loyalty.valueOf(widget.state.redeemablePoints),
                ),
              }),
            ),
          ),
          const SizedBox(height: 10),
        ],

        //? ---- which currency is being handed over -----------------------------
        if (_fx.isUsable) ...<Widget>[
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                label: Text(Fmt.instance.currencySymbol),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text(_fx.code),
              ),
            ],
            selected: <bool>{_foreign},
            onSelectionChanged: (Set<bool> s) => setState(() {
              _foreign = s.first;
              if (_foreign) _method = TenderMethod.cash;
              _pad.clear();
            }),
          ),
          const SizedBox(height: 10),
        ],

        //? ---- how it is being paid -------------------------------------------
        SegmentedButton<TenderMethod>(
          showSelectedIcon: false,
          segments: <ButtonSegment<TenderMethod>>[
            ButtonSegment<TenderMethod>(
              value: TenderMethod.cash,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(context.tr(AppText.cash)),
            ),
            ButtonSegment<TenderMethod>(
              value: TenderMethod.card,
              icon: const Icon(Icons.credit_card, size: 18),
              label: Text(context.tr(AppText.card)),
            ),
            ButtonSegment<TenderMethod>(
              value: TenderMethod.bank,
              icon: const Icon(Icons.account_balance_outlined, size: 18),
              label: Text(context.tr(AppText.bank)),
            ),
          ],
          selected: <TenderMethod>{_method},
          onSelectionChanged: _foreign
              ? null
              : (Set<TenderMethod> s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.surfaces.hairline),
          ),
          child: Row(
            children: <Widget>[
              Text(
                context.tr(AppText.posAmountReceived),
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _pad.text.isEmpty ? '0' : _pad.text,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .merge(theme.tabular),
                  ),
                  if (_foreign && _typedRaw > 0)
                    Text(
                      '${Fmt.moneyMinor(_typedMinor)}'
                      '   ·   ${context.tr(AppText.fxRateNow, params: <String, Object?>{
                            'code': _fx.code,
                            'rate': Fmt.moneyPlain(_fx.toBase(100)),
                          })}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.surfaces.muted),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        //? Round numbers a customer actually hands over. Built from the bill
        //? rather than hardcoded, so they make sense in any currency.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ActionChip(
              avatar: const Icon(Icons.done_all, size: 16),
              label: Text(context.tr(AppText.posExactAmount)),
              onPressed: () => _quick(_outstanding),
            ),
            for (final int amount in _quickAmounts(_outstanding))
              ActionChip(
                label: Text(Fmt.moneyMinor(amount, withSymbol: false)),
                onPressed: () => _quick(amount),
              ),
          ],
        ),
        const SizedBox(height: 12),
        NumberPad(
          allowDecimal: Fmt.instance.decimals > 0,
          onDigit: (String d) => setState(() => _pad.digit(d)),
          onBackspace: () => setState(_pad.backspace),
          onClear: () => setState(_pad.clear),
        ),

        if (_tenders.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          for (int i = 0; i < _tenders.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Icon(_iconFor(_tenders[i].method), size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tenders[i].isForeign
                          ? '${context.tr(_labelFor(_tenders[i].method))} · '
                              '${_fx.format(_tenders[i].amountFxMinor)}'
                          : context.tr(_labelFor(_tenders[i].method)),
                    ),
                  ),
                  Text(
                    Fmt.moneyMinor(_tenders[i].amountMinor),
                    style: theme.textTheme.bodyMedium?.merge(theme.tabular),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: () => setState(() => _tenders.removeAt(i)),
                  ),
                ],
              ),
            ),
        ],

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _typedMinor > 0 ? _addTender : null,
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.tr(AppText.posAddTender)),
        ),

        if (needsCustomer) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(AppText.posNeedCustomer),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (overLimit) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(
                      AppText.posOverCreditLimit,
                      params: <String, Object?>{
                        'name': widget.state.customer?.name ?? '',
                        'amount': Fmt.moneyMinor(
                          widget.state.customer!.balance.minor +
                              preview.dueMinor -
                              widget.state.customer!.creditLimit.minor,
                        ),
                      },
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: needsCustomer || blockedByCredit ? null : _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              preview.dueMinor > 0
                  ? '${context.tr(AppText.posPay)}  ·  ${context.tr(AppText.credit)}'
                  : context.tr(AppText.posPaidInFull),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  void _confirm() {
    final List<TenderInput> result = <TenderInput>[
      ..._tenders,
      if (_typedMinor > 0)
        TenderInput(method: _method, amountMinor: _typedMinor),
    ];
    Navigator.of(context).pop(result);
  }

  //? The notes a customer is likely to hand over for a bill of this size.
  static List<int> _quickAmounts(int outstanding) {
    if (outstanding <= 0) return const <int>[];
    final int major = (outstanding + 99) ~/ 100;
    final List<int> steps = <int>[];
    for (final int step in <int>[1000, 5000, 10000, 25000, 50000, 100000]) {
      final int rounded = ((major + step - 1) ~/ step) * step;
      if (rounded > major && !steps.contains(rounded)) steps.add(rounded);
      if (steps.length == 4) break;
    }
    return steps.map((int m) => m * 100).toList(growable: false);
  }

  static IconData _iconFor(TenderMethod method) => switch (method) {
        TenderMethod.card => Icons.credit_card,
        TenderMethod.bank => Icons.account_balance_outlined,
        TenderMethod.voucher => Icons.confirmation_number_outlined,
        TenderMethod.credit => Icons.schedule_outlined,
        TenderMethod.cash => Icons.payments_outlined,
      };

  static String _labelFor(TenderMethod method) => switch (method) {
        TenderMethod.card => AppText.card,
        TenderMethod.bank => AppText.bank,
        TenderMethod.voucher => AppText.cash,
        TenderMethod.credit => AppText.credit,
        TenderMethod.cash => AppText.cash,
      };
}
