import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sales_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/sales_cubit.dart';
import '../widgets/invoice_detail_sheet.dart';

/// Every invoice the shop has issued, with the day's takings underneath.
///
/// A cashier sees their sales but not the cost or the profit columns — not
/// because the figures are secret, but because a number on a screen at a
/// counter gets read out loud.
class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool canSeeMoney =
        context.select<AuthCubit, bool>((AuthCubit c) => c.state.user?.canSeeMoney ?? true);

    return BlocConsumer<SalesCubit, SalesState>(
      listenWhen: (SalesState a, SalesState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, SalesState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<SalesCubit>().clearFailure();
      },
      builder: (BuildContext context, SalesState state) {
        final SalesCubit cubit = context.read<SalesCubit>();

        return RefreshIndicator(
          onRefresh: cubit.load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              20,
              Responsive.isMobile(context) ? 14 : 24,
              40,
            ),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.salesTitle),
                subtitle:
                    '${Fmt.date(state.query.from.toIso8601String())}  →  ${Fmt.date(state.query.to.toIso8601String())}',
                actions: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _pickRange(context, cubit, state),
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
              const SizedBox(height: 18),
              _Summary(summary: state.summary, canSeeMoney: canSeeMoney),
              const SizedBox(height: 16),
              _Filters(state: state, cubit: cubit),
              const SizedBox(height: 16),
              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.status.isFailure && state.failure != null)
                ErrorNotice(failure: state.failure!, onRetry: cubit.load)
              else
                _Table(state: state, cubit: cubit, canSeeMoney: canSeeMoney),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _pickRange(
    BuildContext context,
    SalesCubit cubit,
    SalesState state,
  ) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDateRange:
          DateTimeRange(start: state.query.from, end: state.query.to),
    );
    if (picked != null) cubit.setRange(picked.start, picked.end);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.canSeeMoney});

  final SalesSummary summary;
  final bool canSeeMoney;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 560
            ? 2
            : constraints.maxWidth < 900
                ? 3
                : (canSeeMoney ? 5 : 4);
        const double gap = 12;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            SizedBox(
              width: width,
              child: KpiCard(
                icon: Icons.receipt_long_outlined,
                label: context.tr(AppText.salesTitle),
                value: Fmt.money(summary.total),
                footnote: '${summary.count}  ${context.tr(AppText.salesInvoice)}',
              ),
            ),
            SizedBox(
              width: width,
              child: KpiCard(
                icon: Icons.payments_outlined,
                label: context.tr(AppText.paid),
                value: Fmt.money(summary.paid),
                tint: AppColors.ok,
              ),
            ),
            SizedBox(
              width: width,
              child: KpiCard(
                icon: Icons.schedule_outlined,
                label: context.tr(AppText.due),
                value: Fmt.money(summary.due),
                tint: AppColors.warning,
              ),
            ),
            SizedBox(
              width: width,
              child: KpiCard(
                icon: Icons.assignment_return_outlined,
                label: context.tr(AppText.salesReturnTitle),
                value: Fmt.money(summary.returnsTotal),
                tint: AppColors.danger,
              ),
            ),
            if (canSeeMoney)
              SizedBox(
                width: width,
                child: KpiCard(
                  icon: Icons.trending_up,
                  label: context.tr(AppText.profit),
                  value: Fmt.money(summary.profit),
                  tint: AppColors.accent,
                  footnote:
                      '${context.tr(AppText.discount)}: ${Fmt.money(summary.discount)}',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.cubit});

  final SalesState state;
  final SalesCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 280,
              child: TextField(
                onChanged: cubit.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.tr(AppText.search),
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'all',
                  label: Text(context.tr(AppText.all)),
                ),
                ButtonSegment<String>(
                  value: 'sale',
                  label: Text(context.tr(AppText.salesTitle)),
                ),
                ButtonSegment<String>(
                  value: 'sale_return',
                  label: Text(context.tr(AppText.salesReturnTitle)),
                ),
              ],
              selected: <String>{state.query.docType ?? 'all'},
              onSelectionChanged: (Set<String> s) =>
                  cubit.filterByDocType(s.first == 'all' ? null : s.first),
            ),
            FilterChip(
              label: Text(context.tr(AppText.due)),
              selected: state.query.onlyUnpaid,
              onSelected: cubit.filterUnpaid,
            ),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.state,
    required this.cubit,
    required this.canSeeMoney,
  });

  final SalesState state;
  final SalesCubit cubit;
  final bool canSeeMoney;

  @override
  Widget build(BuildContext context) {
    return AdminTable<SaleInvoice>(
      rows: state.invoices,
      onRowTap: (SaleInvoice row) => showInvoiceDetail(context, cubit, row.id),
      rowTint: (BuildContext context, SaleInvoice row) =>
          row.isVoid ? Theme.of(context).surfaces.overlay : null,
      empty: EmptyState(
        icon: Icons.receipt_long_outlined,
        message: context.tr(AppText.nothingYet),
      ),
      columns: <AdminColumn<SaleInvoice>>[
        AdminColumn<SaleInvoice>(
          label: context.tr(AppText.invoiceNo),
          flex: 3,
          cell: (BuildContext context, SaleInvoice row) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                row.invoiceNo,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)
                    .merge(Theme.of(context).tabular),
              ),
              Text(
                Fmt.dateTime(row.issuedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AdminColumn<SaleInvoice>(
          label: context.tr(AppText.customer),
          flex: 3,
          hideBelow: 900,
          cell: (BuildContext context, SaleInvoice row) => Text(
            row.partyName ?? context.tr(AppText.posWalkIn),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AdminColumn<SaleInvoice>(
          label: context.tr(AppText.status),
          flex: 2,
          cell: (BuildContext context, SaleInvoice row) => _StatusChip(row: row),
        ),
        AdminColumn<SaleInvoice>(
          label: context.tr(AppText.total),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, SaleInvoice row) => Text(
            Fmt.moneyMinor(row.signedTotalMinor),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: row.isReturn ? AppColors.danger : null,
                )
                .merge(Theme.of(context).tabular),
          ),
        ),
        AdminColumn<SaleInvoice>(
          label: context.tr(AppText.due),
          flex: 2,
          alignEnd: true,
          hideBelow: 1100,
          cell: (BuildContext context, SaleInvoice row) => Text(
            row.due.isZero ? '—' : Fmt.money(row.due),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: row.due.isZero ? null : AppColors.warning)
                .merge(Theme.of(context).tabular),
          ),
        ),
        if (canSeeMoney)
          AdminColumn<SaleInvoice>(
            label: context.tr(AppText.profit),
            flex: 2,
            alignEnd: true,
            hideBelow: 1300,
            cell: (BuildContext context, SaleInvoice row) => Text(
              Fmt.money(row.profit),
              style: Theme.of(context).textTheme.bodySmall?.merge(
                    Theme.of(context).tabular,
                  ),
            ),
          ),
      ],
      mobileCard: (BuildContext context, SaleInvoice row) => AdminRecordCard(
        onTap: () => showInvoiceDetail(context, cubit, row.id),
        title: row.invoiceNo,
        subtitle: '${Fmt.dateTime(row.issuedAt)}  ·  '
            '${row.partyName ?? context.tr(AppText.posWalkIn)}',
        trailing: _StatusChip(row: row),
        details: <Widget>[
          RecordDetail(
            label: context.tr(AppText.total),
            value: Fmt.moneyMinor(row.signedTotalMinor),
          ),
          if (!row.due.isZero)
            RecordDetail(
              label: context.tr(AppText.due),
              value: Fmt.money(row.due),
              color: AppColors.warning,
            ),
          if (canSeeMoney)
            RecordDetail(
              label: context.tr(AppText.profit),
              value: Fmt.money(row.profit),
            ),
        ],
      ),
      footer: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${state.summary.count}  ${context.tr(AppText.salesInvoice)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            Fmt.money(state.summary.total),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.merge(Theme.of(context).tabular),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.row});

  final SaleInvoice row;

  @override
  Widget build(BuildContext context) {
    if (row.isVoid) {
      return StatusChip(
        label: context.tr(AppText.voidLabel),
        color: AppColors.danger,
        compact: true,
      );
    }
    if (row.isReturn) {
      return StatusChip(
        label: context.tr(AppText.salesReturnTitle),
        color: AppColors.info,
        compact: true,
        icon: Icons.assignment_return_outlined,
      );
    }
    if (row.isFullyReturned) {
      return StatusChip(
        label: context.tr(AppText.salesReturned),
        color: AppColors.warning,
        compact: true,
      );
    }
    if (row.isPartlyReturned) {
      return StatusChip(
        label: context.tr(AppText.salesPartiallyReturned),
        color: AppColors.warning,
        compact: true,
      );
    }
    return StatusChip(
      label: context.tr(row.isPaid ? AppText.paid : AppText.credit),
      color: row.isPaid ? AppColors.ok : AppColors.warning,
      compact: true,
    );
  }
}
