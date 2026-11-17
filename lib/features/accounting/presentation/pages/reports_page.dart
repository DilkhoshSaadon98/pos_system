import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/accounting_entities.dart';
import '../cubit/reports_cubit.dart';

/// The three statements a business is measured by.
///
/// Each one is read straight from the journal, and each one shows its own
/// check: the trial balance shows whether it balances, the balance sheet shows
/// whether assets equal liabilities plus equity. A report that cannot fail its
/// own test is a report nobody has reason to believe.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (BuildContext context, ReportsState state) {
        final ReportsCubit cubit = context.read<ReportsCubit>();

        if (state.status.isBusyFirstTime) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status.isFailure && state.failure != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorNotice(failure: state.failure!, onRetry: cubit.load),
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            Responsive.isMobile(context) ? 14 : 24,
            20,
            Responsive.isMobile(context) ? 14 : 24,
            40,
          ),
          children: <Widget>[
            SectionHeader(
              title: context.tr(AppText.navReports),
              subtitle:
                  '${Fmt.date(state.from.toIso8601String())}  →  ${Fmt.date(state.to.toIso8601String())}',
              actions: <Widget>[
                OutlinedButton.icon(
                  onPressed: () async {
                    final DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(DateTime.now().year - 8),
                      lastDate: DateTime(DateTime.now().year + 1),
                      initialDateRange:
                          DateTimeRange(start: state.from, end: state.to),
                    );
                    if (picked != null) {
                      await cubit.setRange(picked.start, picked.end);
                    }
                  },
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(context.tr(AppText.period)),
                ),
                OutlinedButton.icon(
                  onPressed: cubit.load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.tr(AppText.refresh)),
                ),
              ],
            ),
            if (state.missingKeys.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _MissingKeys(keys: state.missingKeys),
            ],
            const SizedBox(height: 18),
            SegmentedButton<ReportTab>(
              showSelectedIcon: false,
              segments: <ButtonSegment<ReportTab>>[
                ButtonSegment<ReportTab>(
                  value: ReportTab.trialBalance,
                  icon: const Icon(Icons.balance, size: 18),
                  label: Text(context.tr(AppText.acctTrialBalance)),
                ),
                ButtonSegment<ReportTab>(
                  value: ReportTab.incomeStatement,
                  icon: const Icon(Icons.trending_up, size: 18),
                  label: Text(context.tr(AppText.acctIncomeStatement)),
                ),
                ButtonSegment<ReportTab>(
                  value: ReportTab.balanceSheet,
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: Text(context.tr(AppText.acctBalanceSheet)),
                ),
              ],
              selected: <ReportTab>{state.tab},
              onSelectionChanged: (Set<ReportTab> s) => cubit.setTab(s.first),
            ),
            const SizedBox(height: 18),
            switch (state.tab) {
              ReportTab.trialBalance =>
                _TrialBalanceView(report: state.trialBalance),
              ReportTab.incomeStatement =>
                _IncomeView(report: state.income),
              ReportTab.balanceSheet =>
                _BalanceSheetView(report: state.balanceSheet),
            },
          ],
        );
      },
    );
  }
}

class _MissingKeys extends StatelessWidget {
  const _MissingKeys({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr(AppText.acctChart),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(keys.join(', '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrialBalanceView extends StatelessWidget {
  const _TrialBalanceView({required this.report});

  final TrialBalance? report;

  @override
  Widget build(BuildContext context) {
    final TrialBalance? r = report;
    if (r == null) {
      return Card(
        child: EmptyState(
          icon: Icons.balance,
          message: context.tr(AppText.nothingYet),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        _BalanceBanner(
          balanced: r.isBalanced,
          difference: r.difference,
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: <Widget>[
              _ReportHeaderRow(
                columns: <String>[
                  context.tr(AppText.acctAccount),
                  context.tr(AppText.acctDebit),
                  context.tr(AppText.acctCredit),
                ],
              ),
              for (final TrialBalanceRow row in r.rows) ...<Widget>[
                Divider(height: 1, color: theme.surfaces.hairline),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 68,
                              child: Text(
                                row.code,
                                style: theme.textTheme.bodySmall
                                    ?.merge(theme.tabular),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                row.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            StatusChip.neutral(
                              context,
                              context.tr(row.type.labelKey),
                            ),
                          ],
                        ),
                      ),
                      _Amount(value: row.debit),
                      _Amount(value: row.credit),
                    ],
                  ),
                ),
              ],
              Divider(height: 1, color: theme.surfaces.hairline),
              Container(
                color: theme.surfaces.raised,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Text(
                        context.tr(AppText.total),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    _Amount(value: r.totalDebit, bold: true),
                    _Amount(value: r.totalCredit, bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IncomeView extends StatelessWidget {
  const _IncomeView({required this.report});

  final IncomeStatement? report;

  @override
  Widget build(BuildContext context) {
    final IncomeStatement? r = report;
    if (r == null) {
      return Card(
        child: EmptyState(
          icon: Icons.trending_up,
          message: context.tr(AppText.nothingYet),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    final bool profit = !r.netProfit.isNegative;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Group(
              title: context.tr(AppText.acctRevenue),
              lines: r.revenue,
            ),
            if (r.contra.isNotEmpty)
              _Group(
                title: context.tr(AppText.discount),
                lines: r.contra,
                negative: true,
              ),
            TotalRow(
              label: context.tr(AppText.acctRevenue),
              value: Fmt.money(r.netRevenue),
              emphasis: true,
            ),
            Divider(height: 24, color: theme.surfaces.hairline),
            _Group(
              title: context.tr(AppText.acctCogs),
              lines: r.cogs,
              negative: true,
            ),
            TotalRow(
              label: context.tr(AppText.acctGrossProfit),
              value: Fmt.money(r.grossProfit),
              emphasis: true,
              color: r.grossProfit.isNegative ? AppColors.danger : AppColors.ok,
            ),
            Divider(height: 24, color: theme.surfaces.hairline),
            _Group(
              title: context.tr(AppText.acctExpenses),
              lines: r.expenses,
              negative: true,
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (profit ? AppColors.ok : AppColors.danger)
                    .withValues(alpha: theme.isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TotalRow(
                emphasis: true,
                label: context.tr(
                  profit ? AppText.acctNetProfit : AppText.acctNetLoss,
                ),
                value: Fmt.money(profit ? r.netProfit : r.netProfit.abs),
                color: profit ? AppColors.ok : AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.lines,
    this.negative = false,
  });

  final String title;
  final List<IncomeLine> lines;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.7,
              color: theme.surfaces.muted,
            ),
          ),
        ),
        for (final IncomeLine line in lines)
          TotalRow(
            label: '${line.code}  ${line.name}',
            value: negative
                ? '−${Fmt.money(line.amount)}'
                : Fmt.money(line.amount),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _BalanceSheetView extends StatelessWidget {
  const _BalanceSheetView({required this.report});

  final BalanceSheet? report;

  @override
  Widget build(BuildContext context) {
    final BalanceSheet? r = report;
    if (r == null) {
      return Card(
        child: EmptyState(
          icon: Icons.account_balance_outlined,
          message: context.tr(AppText.nothingYet),
        ),
      );
    }

    final Widget left = _SheetColumn(
      title: context.tr(AppText.acctAssets),
      accounts: r.assets,
      total: r.totalAssets,
      totalLabel: context.tr(AppText.acctTotalAssets),
    );

    final Widget right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SheetColumn(
          title: context.tr(AppText.acctLiabilities),
          accounts: r.liabilities,
          total: r.totalLiabilities,
          totalLabel: context.tr(AppText.acctLiabilities),
        ),
        const SizedBox(height: 12),
        _SheetColumn(
          title: context.tr(AppText.acctEquity),
          accounts: r.equity,
          total: r.totalEquity,
          totalLabel: context.tr(AppText.acctEquity),
          extra: TotalRow(
            label: context.tr(AppText.acctCurrentEarnings),
            value: Fmt.money(r.currentEarnings),
            color: r.currentEarnings.isNegative
                ? AppColors.danger
                : AppColors.ok,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TotalRow(
              emphasis: true,
              label: context.tr(AppText.acctTotalLiabEquity),
              value: Fmt.money(r.totalLiabilitiesAndEquity),
            ),
          ),
        ),
      ],
    );

    return Column(
      children: <Widget>[
        _BalanceBanner(balanced: r.isBalanced, difference: r.difference),
        const SizedBox(height: 12),
        if (Responsive.isCompact(context))
          Column(children: <Widget>[left, const SizedBox(height: 12), right])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          ),
      ],
    );
  }
}

class _SheetColumn extends StatelessWidget {
  const _SheetColumn({
    required this.title,
    required this.accounts,
    required this.total,
    required this.totalLabel,
    this.extra,
  });

  final String title;
  final List<Account> accounts;
  final Money total;
  final String totalLabel;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(dense: true, title: title),
            const SizedBox(height: 10),
            if (accounts.isEmpty && extra == null)
              Text(context.tr(AppText.nothingYet),
                  style: theme.textTheme.bodySmall)
            else ...<Widget>[
              for (final Account a in accounts)
                TotalRow(
                  label: '${a.code}  ${a.name}',
                  value: Fmt.money(a.balance),
                ),
              if (extra != null) extra!,
            ],
            Divider(height: 20, color: theme.surfaces.hairline),
            TotalRow(emphasis: true, label: totalLabel, value: Fmt.money(total)),
          ],
        ),
      ),
    );
  }
}

class _BalanceBanner extends StatelessWidget {
  const _BalanceBanner({required this.balanced, required this.difference});

  final bool balanced;
  final Money difference;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = balanced ? AppColors.ok : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: theme.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(balanced ? Icons.check_circle_outline : Icons.error_outline,
              size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              balanced
                  ? context.tr(AppText.acctBalanced)
                  : context.tr(
                      AppText.acctOutOfBalance,
                      params: <String, Object?>{
                        'amount': Fmt.money(difference),
                      },
                    ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.readableOnTint(color, theme.brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportHeaderRow extends StatelessWidget {
  const _ReportHeaderRow({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surfaces.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(columns.first, style: theme.textTheme.labelSmall),
          ),
          for (final String c in columns.skip(1))
            SizedBox(
              width: 130,
              child: Text(
                c,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.value, this.bold = false});

  final Money value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 130,
      child: Text(
        value.isZero ? '' : Fmt.money(value, withSymbol: false),
        textAlign: TextAlign.end,
        style: theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: bold ? FontWeight.w700 : null)
            .merge(theme.tabular),
      ),
    );
  }
}
