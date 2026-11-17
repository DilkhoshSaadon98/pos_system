import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../parties/domain/repositories/parties_repository.dart';
import '../../domain/entities/purchase_document.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../cubit/purchase_editor_cubit.dart';
import '../cubit/purchases_cubit.dart';
import '../widgets/purchase_editor_sheet.dart';

/// Everything the shop has bought, and the button that adds another one.
class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PurchasesCubit, PurchasesState>(
      listenWhen: (PurchasesState a, PurchasesState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, PurchasesState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PurchasesCubit>().clearFailure();
      },
      builder: (BuildContext context, PurchasesState state) {
        final PurchasesCubit cubit = context.read<PurchasesCubit>();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Responsive.isMobile(context)
              ? FloatingActionButton.extended(
                  onPressed: () => _newPurchase(context, cubit),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr(AppText.purchaseNew)),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Responsive.isMobile(context) ? 14 : 24,
                20,
                Responsive.isMobile(context) ? 14 : 24,
                90,
              ),
              children: <Widget>[
                SectionHeader(
                  title: context.tr(AppText.purchaseTitle),
                  subtitle:
                      '${Fmt.date(state.query.from.toIso8601String())}  →  ${Fmt.date(state.query.to.toIso8601String())}',
                  actions: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final DateTimeRange? picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(DateTime.now().year - 5),
                          lastDate: DateTime(DateTime.now().year + 1),
                          initialDateRange: DateTimeRange(
                            start: state.query.from,
                            end: state.query.to,
                          ),
                        );
                        if (picked != null) {
                          cubit.setRange(picked.start, picked.end);
                        }
                      },
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(context.tr(AppText.period)),
                    ),
                    if (!Responsive.isMobile(context))
                      FilledButton.icon(
                        onPressed: () => _newPurchase(context, cubit),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.tr(AppText.purchaseNew)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _Summary(summary: state.summary),
                const SizedBox(height: 16),
                Card(
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
                              value: 'purchase',
                              label: Text(context.tr(AppText.purchaseTitle)),
                            ),
                            ButtonSegment<String>(
                              value: 'purchase_return',
                              label:
                                  Text(context.tr(AppText.purchaseReturnTitle)),
                            ),
                          ],
                          selected: <String>{state.query.docType ?? 'all'},
                          onSelectionChanged: (Set<String> s) => cubit
                              .filterByDocType(s.first == 'all' ? null : s.first),
                        ),
                        FilterChip(
                          label: Text(context.tr(AppText.due)),
                          selected: state.query.onlyUnpaid,
                          onSelected: cubit.filterUnpaid,
                        ),
                      ],
                    ),
                  ),
                ),
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
                  _Table(state: state, cubit: cubit),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _newPurchase(
    BuildContext context,
    PurchasesCubit list,
  ) async {
    final AppDatabase database = sl<AppDatabase>();
    final PurchaseEditorCubit editor = PurchaseEditorCubit(
      purchases: sl<PurchasesRepository>(),
      catalog: sl<CatalogRepository>(),
      parties: sl<PartiesRepository>(),
      defaultTaxRateBp: database.settingInt('default_tax_rate_bp'),
      roundingStepMinor: database.settingInt('rounding_step_minor'),
    )..load();

    final PostedPurchase? posted = await showPurchaseEditor(context, editor);
    await editor.close();
    if (posted != null) await list.load();
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final PurchasesSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth < 560 ? 2 : 4;
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
                icon: Icons.local_shipping_outlined,
                label: context.tr(AppText.purchaseTitle),
                value: Fmt.money(summary.total),
                footnote: '${summary.count}',
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
                icon: Icons.local_gas_station_outlined,
                label: context.tr(AppText.purchaseFees),
                value: Fmt.money(summary.fees),
                tint: AppColors.info,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.state, required this.cubit});

  final PurchasesState state;
  final PurchasesCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<PurchaseInvoice>(
      rows: state.invoices,
      onRowTap: (PurchaseInvoice row) => _showDetail(context, row),
      rowTint: (BuildContext context, PurchaseInvoice row) =>
          row.isVoid ? Theme.of(context).surfaces.overlay : null,
      empty: EmptyState(
        icon: Icons.local_shipping_outlined,
        message: context.tr(AppText.nothingYet),
      ),
      columns: <AdminColumn<PurchaseInvoice>>[
        AdminColumn<PurchaseInvoice>(
          label: context.tr(AppText.invoiceNo),
          flex: 3,
          cell: (BuildContext context, PurchaseInvoice row) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                row.invoiceNo,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                <String>[
                  Fmt.dateTime(row.issuedAt),
                  if ((row.supplierRef ?? '').isNotEmpty) row.supplierRef!,
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AdminColumn<PurchaseInvoice>(
          label: context.tr(AppText.supplier),
          flex: 3,
          hideBelow: 900,
          cell: (BuildContext context, PurchaseInvoice row) =>
              Text(row.partyName ?? '—', overflow: TextOverflow.ellipsis),
        ),
        AdminColumn<PurchaseInvoice>(
          label: context.tr(AppText.status),
          flex: 2,
          cell: (BuildContext context, PurchaseInvoice row) => StatusChip(
            compact: true,
            label: context.tr(
              row.isVoid
                  ? AppText.voidLabel
                  : row.isReturn
                      ? AppText.purchaseReturnTitle
                      : row.isPaid
                          ? AppText.paid
                          : AppText.credit,
            ),
            color: row.isVoid
                ? AppColors.danger
                : row.isReturn
                    ? AppColors.info
                    : row.isPaid
                        ? AppColors.ok
                        : AppColors.warning,
          ),
        ),
        AdminColumn<PurchaseInvoice>(
          label: context.tr(AppText.total),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, PurchaseInvoice row) => Text(
            Fmt.moneyMinor(row.signedTotalMinor),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: row.isReturn ? AppColors.info : null,
                )
                .merge(Theme.of(context).tabular),
          ),
        ),
        AdminColumn<PurchaseInvoice>(
          label: context.tr(AppText.due),
          flex: 2,
          alignEnd: true,
          hideBelow: 1100,
          cell: (BuildContext context, PurchaseInvoice row) => Text(
            row.due.isZero ? '—' : Fmt.money(row.due),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: row.due.isZero ? null : AppColors.warning,
                ),
          ),
        ),
      ],
      mobileCard: (BuildContext context, PurchaseInvoice row) =>
          AdminRecordCard(
        onTap: () => _showDetail(context, row),
        title: row.invoiceNo,
        subtitle: '${Fmt.dateTime(row.issuedAt)}  ·  ${row.partyName ?? ''}',
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
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, PurchaseInvoice row) async {
    final PurchaseInvoiceDetail? detail = await cubit.detail(row.id);
    if (detail == null || !context.mounted) return;

    final bool canVoid =
        context.read<AuthCubit>().state.user?.canVoid ?? true;
    final int? userId = context.read<AuthCubit>().state.user?.id;

    await showAppModal<void>(
      context,
      width: 720,
      title: detail.invoice.invoiceNo,
      subtitle: detail.invoice.partyName,
      builder: (BuildContext modalContext) {
        final ThemeData theme = Theme.of(modalContext);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.surfaces.hairline),
              ),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < detail.lines.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(height: 1, color: theme.surfaces.hairline),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(detail.lines[i].itemName),
                                Text(
                                  '${Fmt.qtyMilli(detail.lines[i].qtyMilli)} ${detail.lines[i].unitName}'
                                  '  ·  ${Fmt.money(detail.lines[i].unitCost)}'
                                  '  ·  ${modalContext.tr(AppText.purchaseLandedCost)} ${Fmt.money(detail.lines[i].landedUnitCost)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Fmt.money(detail.lines[i].landedTotal),
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surfaces.raised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: <Widget>[
                  if (!detail.invoice.fees.isZero)
                    TotalRow(
                      label: modalContext.tr(AppText.purchaseFees),
                      value: Fmt.money(detail.invoice.fees),
                    ),
                  if (!detail.invoice.discount.isZero)
                    TotalRow(
                      label: modalContext.tr(AppText.discount),
                      value: '−${Fmt.money(detail.invoice.discount)}',
                    ),
                  if (!detail.invoice.tax.isZero)
                    TotalRow(
                      label: modalContext.tr(AppText.tax),
                      value: Fmt.money(detail.invoice.tax),
                    ),
                  TotalRow(
                    emphasis: true,
                    label: modalContext.tr(AppText.total),
                    value: Fmt.money(detail.invoice.total),
                  ),
                  TotalRow(
                    label: modalContext.tr(AppText.due),
                    value: Fmt.money(detail.invoice.due),
                    color: detail.invoice.due.isZero ? null : AppColors.warning,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                if (canVoid && !detail.invoice.isVoid)
                  TextButton.icon(
                    onPressed: () async {
                      final bool ok = await confirm(
                        modalContext,
                        icon: Icons.block_outlined,
                        title: modalContext.tr(AppText.salesVoid),
                        message: modalContext.tr(AppText.salesVoidConfirm),
                        confirmLabel: modalContext.tr(AppText.salesVoid),
                      );
                      if (!ok || !modalContext.mounted) return;
                      final bool done = await cubit.voidPurchase(
                        detail.invoice.id,
                        userId: userId,
                      );
                      if (!modalContext.mounted) return;
                      if (done) {
                        AppSnack.success(modalContext,
                            modalContext.tr(AppText.salesVoided));
                        Navigator.of(modalContext).pop();
                      } else {
                        final String? d = cubit.state.failure?.detail;
                        if (d != null) AppSnack.error(modalContext, d);
                      }
                    },
                    icon: const Icon(Icons.block_outlined, size: 18),
                    label: Text(modalContext.tr(AppText.salesVoid)),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.danger),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(modalContext).pop(),
                  child: Text(modalContext.tr(AppText.close)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
