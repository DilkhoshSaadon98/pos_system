import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/fx.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/shift.dart';
import '../cubit/shift_cubit.dart';

/// The drawer: opening it, watching it, counting it.
///
/// The screen is built around one question a cashier asks at the end of a
/// shift — *does the money in my hand match what the system says?* — so the
/// expected figure is on screen the whole time rather than appearing only
/// after the count is typed. Nothing here hides a difference: an overage is as
/// visible as a shortage, because a till that is regularly over is as much of
/// a problem as one that is short.
class ShiftsPage extends StatelessWidget {
  const ShiftsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ShiftCubit, ShiftState>(
      listenWhen: (ShiftState a, ShiftState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, ShiftState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<ShiftCubit>().clearFailure();
      },
      builder: (BuildContext context, ShiftState state) {
        final ShiftCubit cubit = context.read<ShiftCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.shiftsTitle),
                subtitle: state.hasOpenShift
                    ? context.tr(AppText.shiftStatusOpen)
                    : context.tr(AppText.shiftNone),
                actions: <Widget>[
                  if (state.hasOpenShift) ...<Widget>[
                    OutlinedButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => cubit.showReport(state.current!.id),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(context.tr(AppText.shiftXReport)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed:
                          state.busy ? null : () => _close(context, cubit, state),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: Text(context.tr(AppText.shiftClose)),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed:
                          state.busy ? null : () => _open(context, cubit),
                      icon: const Icon(Icons.lock_open_outlined, size: 18),
                      label: Text(context.tr(AppText.shiftOpen)),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.status.isFailure && state.failure != null)
                ErrorNotice(failure: state.failure!, onRetry: cubit.load)
              else ...<Widget>[
                if (!state.hasOpenShift) _ClosedDrawerNotice(cubit: cubit),
                if (state.report != null) ...<Widget>[
                  _ReportCard(report: state.report!, fx: cubit.fx),
                  const SizedBox(height: 22),
                ],
                SectionHeader(
                  title: context.tr(AppText.shiftHistory),
                  subtitle: '${state.history.length}',
                  dense: true,
                ),
                const SizedBox(height: 10),
                _HistoryTable(state: state, cubit: cubit),
              ],
            ],
          ),
        );
      },
    );
  }

  static Future<void> _open(BuildContext context, ShiftCubit cubit) async {
    await showAppModal<void>(
      context,
      title: context.tr(AppText.shiftOpen),
      subtitle: context.tr(AppText.shiftOpenHint),
      width: 520,
      builder: (BuildContext modalContext) =>
          _CountForm(cubit: cubit, closing: false),
    );
  }

  static Future<void> _close(
    BuildContext context,
    ShiftCubit cubit,
    ShiftState state,
  ) async {
    await showAppModal<void>(
      context,
      title: context.tr(AppText.shiftClose),
      subtitle: state.current?.shiftNo,
      width: 520,
      builder: (BuildContext modalContext) =>
          _CountForm(cubit: cubit, closing: true),
    );
  }
}

/// The one form used to open and to close, because a count is a count.
class _CountForm extends StatefulWidget {
  const _CountForm({required this.cubit, required this.closing});

  final ShiftCubit cubit;
  final bool closing;

  @override
  State<_CountForm> createState() => _CountFormState();
}

class _CountFormState extends State<_CountForm> {
  final TextEditingController _cash = TextEditingController();
  final TextEditingController _foreign = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cash.dispose();
    _foreign.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _cashMinor => (MoneyField.read(_cash) ?? Money.zero).minor;

  /// The foreign box is typed in that currency's own units — dollars, not
  /// dinars. Both currencies are stored at the same scale, so no rescaling is
  /// needed here; the conversion happens once, when it is posted.
  int get _foreignMinor => (MoneyField.read(_foreign) ?? Money.zero).minor;

  @override
  Widget build(BuildContext context) {
    final FxRate fx = widget.cubit.fx;
    final ShiftReport? report = widget.cubit.state.report;
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.closing && report != null) ...<Widget>[
          TotalRow(
            label: context.tr(AppText.shiftExpected),
            value: Fmt.money(report.expected),
            emphasis: true,
          ),
          if (fx.isUsable && report.expectedFxMinor != 0)
            TotalRow(
              label: '${context.tr(AppText.shiftExpected)} · ${fx.code}',
              value: fx.format(report.expectedFxMinor),
            ),
          const Divider(height: 26),
        ],
        MoneyField(
          controller: _cash,
          autofocus: true,
          label: widget.closing
              ? context.tr(AppText.shiftCounted)
              : context.tr(AppText.shiftOpeningFloat),
          helper: widget.closing
              ? context.tr(AppText.shiftCountedHint)
              : context.tr(AppText.shiftOpeningFloatHint),
        ),
        if (fx.isUsable) ...<Widget>[
          const SizedBox(height: 14),
          AppTextField(
            controller: _foreign,
            label: '${widget.closing ? context.tr(AppText.shiftCounted) : context.tr(AppText.shiftOpeningFloat)} · ${fx.code}',
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            helper: context.tr(AppText.fxRateNow, params: <String, Object?>{
              'rate': Fmt.moneyPlain(fx.toBase(100)),
              'code': fx.code,
            }),
          ),
        ],
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: context.tr(AppText.note),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        Text(
          widget.closing
              ? context.tr(AppText.shiftCloseExplain)
              : context.tr(AppText.shiftOpenExplain),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.surfaces.muted),
        ),
        const SizedBox(height: 18),
        ModalActions(
          busy: _busy,
          saveLabel: widget.closing
              ? context.tr(AppText.shiftClose)
              : context.tr(AppText.shiftOpen),
          onSave: _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final String? note = _note.text.trim().isEmpty ? null : _note.text.trim();

    final bool ok;
    if (widget.closing) {
      ok = await widget.cubit.closeShift(
            countedMinor: _cashMinor,
            countedFxMinor: _foreignMinor,
            note: note,
          ) !=
          null;
    } else {
      ok = await widget.cubit.open(
        floatMinor: _cashMinor,
        floatFxMinor: _foreignMinor,
        note: note,
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }
}

/// Shown when there is no open drawer — the till will not sell until there is.
class _ClosedDrawerNotice extends StatelessWidget {
  const _ClosedDrawerNotice({required this.cubit});

  final ShiftCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.point_of_sale_outlined, color: AppColors.warning),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr(AppText.shiftNone),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  cubit.shiftsRequired
                      ? context.tr(AppText.shiftRequiredWarning)
                      : context.tr(AppText.shiftOpenHint),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.surfaces.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The X or Z report: what came in, what went back out, what should be there.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.fx});

  final ShiftReport report;
  final FxRate fx;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CashShift shift = report.shift;
    final bool mobile = Responsive.isMobile(context);

    return Container(
      padding: EdgeInsets.all(mobile ? 16 : 22),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.surfaces.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SectionHeader(
                  dense: true,
                  title: report.isFinal
                      ? context.tr(AppText.shiftZReport)
                      : context.tr(AppText.shiftXReport),
                  subtitle: '${shift.shiftNo} · ${shift.userName ?? ''}',
                ),
              ),
              StatusChip(
                label: shift.isOpen
                    ? context.tr(AppText.shiftStatusOpen)
                    : context.tr(AppText.shiftStatusClosed),
                color: shift.isOpen ? AppColors.success : theme.surfaces.muted,
                icon: shift.isOpen ? Icons.lock_open : Icons.lock_outline,
              ),
            ],
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: mobile ? double.infinity : 220,
                child: KpiCard(
                  label: context.tr(AppText.shiftSales),
                  value: Fmt.money(shift.salesTotal),
                  footnote: '${shift.salesCount}',
                  icon: Icons.shopping_bag_outlined,
                ),
              ),
              SizedBox(
                width: mobile ? double.infinity : 220,
                child: KpiCard(
                  label: context.tr(AppText.shiftReturns),
                  value: Fmt.money(shift.returnsTotal),
                  footnote: '${shift.returnsCount}',
                  icon: Icons.assignment_return_outlined,
                  tint: shift.returnsCount > 0 ? AppColors.warning : null,
                ),
              ),
              SizedBox(
                width: mobile ? double.infinity : 220,
                child: KpiCard(
                  label: context.tr(AppText.shiftExpected),
                  value: Fmt.money(report.expected),
                  icon: Icons.savings_outlined,
                ),
              ),
              if (fx.isUsable)
                SizedBox(
                  width: mobile ? double.infinity : 220,
                  child: KpiCard(
                    label: '${context.tr(AppText.shiftExpected)} · ${fx.code}',
                    value: fx.format(report.expectedFxMinor),
                    icon: Icons.currency_exchange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          Text(
            context.tr(AppText.shiftTenders),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (report.tenders.isEmpty)
            Text(
              context.tr(AppText.nothingYet),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.surfaces.muted),
            )
          else
            ...report.tenders.map((ShiftTenderRow row) => TotalRow(
                  label: '${_methodLabel(context, row.method)}'
                      '${row.isForeign ? ' · ${row.currencyCode}' : ''}'
                      '${row.isIn ? '' : ' · ${context.tr(AppText.shiftGivenBack)}'}'
                      '  (${row.count})',
                  value: row.isForeign
                      ? '${fx.format(row.amountFxMinor)}  ·  ${Fmt.money(row.amount)}'
                      : Fmt.money(row.amount),
                  color: row.isIn ? null : AppColors.danger,
                )),

          const Divider(height: 28),
          TotalRow(
            label: context.tr(AppText.shiftOpeningFloat),
            value: Fmt.money(shift.openingFloat),
          ),
          TotalRow(
            label: context.tr(AppText.shiftCashMovement),
            value: Fmt.money(shift.cashMovement),
          ),
          TotalRow(
            label: context.tr(AppText.shiftExpected),
            value: Fmt.money(report.expected),
            emphasis: true,
          ),
          if (!shift.isOpen) ...<Widget>[
            TotalRow(
              label: context.tr(AppText.shiftCounted),
              value: Fmt.money(shift.counted ?? Money.zero),
              emphasis: true,
            ),
            TotalRow(
              label: context.tr(AppText.shiftDifference),
              value: Fmt.money(shift.difference ?? Money.zero),
              emphasis: true,
              color: shift.isBalanced
                  ? AppColors.success
                  : (shift.isShort ? AppColors.danger : AppColors.warning),
              icon: shift.isBalanced
                  ? Icons.check_circle_outline
                  : Icons.report_problem_outlined,
            ),
          ],
        ],
      ),
    );
  }

  static String _methodLabel(BuildContext context, TenderMethod method) {
    switch (method) {
      case TenderMethod.cash:
        return context.tr(AppText.cash);
      case TenderMethod.card:
        return context.tr(AppText.card);
      case TenderMethod.bank:
        return context.tr(AppText.bank);
      case TenderMethod.voucher:
        return context.tr(AppText.voucher);
      case TenderMethod.credit:
        return context.tr(AppText.credit);
    }
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.state, required this.cubit});

  final ShiftState state;
  final ShiftCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<CashShift>(
      rows: state.history,
      onRowTap: (CashShift row) => cubit.showReport(row.id),
      empty: EmptyState(
        icon: Icons.point_of_sale_outlined,
        message: context.tr(AppText.nothingYet),
      ),
      mobileCard: (BuildContext context, CashShift row) => AdminRecordCard(
        title: row.shiftNo,
        subtitle: '${row.userName ?? ''} · ${Fmt.dateTime(row.openedAt)}',
        trailing: Text(Fmt.money(row.salesTotal)),
        onTap: () => cubit.showReport(row.id),
        details: <Widget>[
          RecordDetail(
            label: context.tr(AppText.shiftDifference),
            value: Fmt.money(row.difference ?? Money.zero),
          ),
          RecordDetail(
            label: context.tr(AppText.shiftSales),
            value: '${row.salesCount}',
          ),
        ],
      ),
      columns: <AdminColumn<CashShift>>[
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftNumber),
          flex: 3,
          cell: (BuildContext context, CashShift row) => Text(row.shiftNo),
        ),
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftCashier),
          flex: 3,
          hideBelow: 900,
          cell: (BuildContext context, CashShift row) =>
              Text(row.userName ?? '—'),
        ),
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftOpenedAt),
          flex: 3,
          cell: (BuildContext context, CashShift row) =>
              Text(Fmt.dateTime(row.openedAt)),
        ),
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftClosedAt),
          flex: 3,
          hideBelow: 1100,
          cell: (BuildContext context, CashShift row) =>
              Text(row.closedAt == null ? '—' : Fmt.dateTime(row.closedAt)),
        ),
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftSales),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, CashShift row) =>
              Text(Fmt.money(row.salesTotal)),
        ),
        AdminColumn<CashShift>(
          label: context.tr(AppText.shiftDifference),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, CashShift row) {
            if (row.isOpen) {
              return StatusChip(
                label: context.tr(AppText.shiftStatusOpen),
                color: AppColors.success,
                compact: true,
              );
            }
            return Text(
              Fmt.money(row.difference ?? Money.zero),
              style: TextStyle(
                color: row.isBalanced
                    ? null
                    : (row.isShort ? AppColors.danger : AppColors.warning),
                fontWeight: row.isBalanced ? null : FontWeight.w700,
              ),
            );
          },
        ),
      ],
    );
  }
}
