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
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/accounting_entities.dart';
import '../cubit/journal_cubit.dart';
import '../widgets/voucher_editor_sheet.dart';

/// Every posting the system has made, and the place to make one by hand.
///
/// A shop rarely needs a hand-written voucher — an owner's drawing, a rent
/// payment, an opening balance — but when it does, there has to be a door. This
/// is that door, and it goes through the same `Journal.post` as everything
/// else, so it cannot produce an entry the rest of the system would not accept.
class JournalPage extends StatelessWidget {
  const JournalPage({super.key});

  static const List<String> _sources = <String>[
    'sale',
    'sale_return',
    'purchase',
    'purchase_return',
    'receipt',
    'payment',
    'opening',
    'adjustment',
    'manual',
  ];

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<JournalCubit, JournalState>(
      listenWhen: (JournalState a, JournalState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, JournalState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<JournalCubit>().clearFailure();
      },
      builder: (BuildContext context, JournalState state) {
        final JournalCubit cubit = context.read<JournalCubit>();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Responsive.isMobile(context)
              ? FloatingActionButton.extended(
                  onPressed: () => showVoucherEditor(context, cubit),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr(AppText.acctJournalNew)),
                )
              : null,
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              20,
              Responsive.isMobile(context) ? 14 : 24,
              90,
            ),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.acctJournal),
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
                        cubit.setRange(picked.start, picked.end);
                      }
                    },
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(context.tr(AppText.period)),
                  ),
                  if (!Responsive.isMobile(context))
                    FilledButton.icon(
                      onPressed: () => showVoucherEditor(context, cubit),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.tr(AppText.acctJournalNew)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      TextField(
                        onChanged: cubit.search,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: context.tr(AppText.search),
                          prefixIcon: const Icon(Icons.search, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(context.tr(AppText.all)),
                                selected: state.sourceType == null,
                                onSelected: (_) => cubit.filterSource(null),
                              ),
                            ),
                            for (final String s in _sources)
                              Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(end: 8),
                                child: ChoiceChip(
                                  label: Text(context.tr(_sourceLabel(s))),
                                  selected: state.sourceType == s,
                                  onSelected: (_) => cubit.filterSource(s),
                                ),
                              ),
                          ],
                        ),
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
        );
      },
    );
  }

  static String _sourceLabel(String source) => switch (source) {
        'sale' => AppText.salesTitle,
        'sale_return' => AppText.salesReturnTitle,
        'purchase' => AppText.purchaseTitle,
        'purchase_return' => AppText.purchaseReturnTitle,
        'receipt' => AppText.partiesReceipt,
        'payment' => AppText.partiesPayment,
        'opening' => AppText.openingBalance,
        'adjustment' => AppText.stockAdjust,
        _ => AppText.acctJournalNew,
      };
}

class _Table extends StatelessWidget {
  const _Table({required this.state, required this.cubit});

  final JournalState state;
  final JournalCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<JournalEntry>(
      rows: state.entries,
      onRowTap: (JournalEntry row) => _showDetail(context, row),
      empty: EmptyState(
        icon: Icons.menu_book_outlined,
        message: context.tr(AppText.nothingYet),
      ),
      columns: <AdminColumn<JournalEntry>>[
        AdminColumn<JournalEntry>(
          label: context.tr(AppText.acctEntryNo),
          flex: 3,
          cell: (BuildContext context, JournalEntry row) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                row.entryNo,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)
                    .merge(Theme.of(context).tabular),
              ),
              Text(
                Fmt.date(row.entryDate),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AdminColumn<JournalEntry>(
          label: context.tr(AppText.acctMemo),
          flex: 5,
          cell: (BuildContext context, JournalEntry row) => Text(
            row.memo ?? '—',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        AdminColumn<JournalEntry>(
          label: context.tr(AppText.acctSource),
          flex: 2,
          hideBelow: 1000,
          cell: (BuildContext context, JournalEntry row) => StatusChip.neutral(
            context,
            row.sourceType,
          ),
        ),
        AdminColumn<JournalEntry>(
          label: context.tr(AppText.total),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, JournalEntry row) => Text(
            Fmt.money(row.debit),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: row.isBalanced ? null : AppColors.danger,
                )
                .merge(Theme.of(context).tabular),
          ),
        ),
      ],
      mobileCard: (BuildContext context, JournalEntry row) => AdminRecordCard(
        onTap: () => _showDetail(context, row),
        title: row.entryNo,
        subtitle: '${Fmt.date(row.entryDate)}  ·  ${row.sourceType}',
        trailing: Text(Fmt.money(row.debit)),
        details: <Widget>[
          if (row.memo != null)
            RecordDetail(
              label: context.tr(AppText.acctMemo),
              value: row.memo!,
            ),
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, JournalEntry row) async {
    final JournalEntryDetail? detail = await cubit.detail(row.id);
    if (detail == null || !context.mounted) return;

    final int? userId = context.read<AuthCubit>().state.user?.id;

    await showAppModal<void>(
      context,
      width: 680,
      title: detail.entry.entryNo,
      subtitle:
          '${Fmt.date(detail.entry.entryDate)}  ·  ${detail.entry.sourceType}',
      builder: (BuildContext modalContext) {
        final ThemeData theme = Theme.of(modalContext);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (detail.entry.memo != null) ...<Widget>[
              Text(detail.entry.memo!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 14),
            ],
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
                          horizontal: 16, vertical: 11),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  '${detail.lines[i].accountCode}  ${detail.lines[i].accountName}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if ((detail.lines[i].partyName ?? '')
                                    .isNotEmpty)
                                  Text(
                                    detail.lines[i].partyName!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              detail.lines[i].debit.isZero
                                  ? ''
                                  : Fmt.money(detail.lines[i].debit,
                                      withSymbol: false),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium
                                  ?.merge(theme.tabular),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              detail.lines[i].credit.isZero
                                  ? ''
                                  : Fmt.money(detail.lines[i].credit,
                                      withSymbol: false),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium
                                  ?.merge(theme.tabular),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Divider(height: 1, color: theme.surfaces.hairline),
                  Container(
                    color: theme.surfaces.raised,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 4,
                          child: Text(
                            modalContext.tr(AppText.total),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            Fmt.money(detail.entry.debit, withSymbol: false),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleSmall
                                ?.merge(theme.tabular),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            Fmt.money(detail.entry.credit, withSymbol: false),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleSmall
                                ?.merge(theme.tabular),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () async {
                    final bool ok = await confirm(
                      modalContext,
                      icon: Icons.undo,
                      title: modalContext.tr(AppText.acctReverse),
                      message: modalContext.tr(AppText.acctReverseConfirm),
                      confirmLabel: modalContext.tr(AppText.acctReverse),
                    );
                    if (!ok || !modalContext.mounted) return;
                    final bool done =
                        await cubit.reverse(detail.entry.id, userId: userId);
                    if (!modalContext.mounted) return;
                    if (done) {
                      AppSnack.success(
                          modalContext, modalContext.tr(AppText.acctReversed));
                      Navigator.of(modalContext).pop();
                    } else {
                      final String? d = cubit.state.failure?.detail;
                      if (d != null) AppSnack.error(modalContext, d);
                    }
                  },
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(modalContext.tr(AppText.acctReverse)),
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
