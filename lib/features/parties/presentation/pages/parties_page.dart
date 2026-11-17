import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/party.dart';
import '../cubit/parties_cubit.dart';
import '../widgets/party_form_sheet.dart';
import '../widgets/settlement_sheet.dart';
import '../widgets/statement_sheet.dart';

/// Customers, or suppliers — the same screen, pointed at the other side of the
/// ledger.
class PartiesPage extends StatelessWidget {
  const PartiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PartiesCubit, PartiesState>(
      listenWhen: (PartiesState a, PartiesState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, PartiesState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PartiesCubit>().clearFailure();
      },
      builder: (BuildContext context, PartiesState state) {
        final PartiesCubit cubit = context.read<PartiesCubit>();
        final bool customers = state.isCustomers;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Responsive.isMobile(context)
              ? FloatingActionButton.extended(
                  onPressed: () => showPartyForm(context, cubit, null),
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(context.tr(customers
                      ? AppText.partiesNewCustomer
                      : AppText.partiesNewSupplier)),
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
                  title: context.tr(customers
                      ? AppText.partiesCustomers
                      : AppText.partiesSuppliers),
                  subtitle: '${state.parties.length}',
                  actions: <Widget>[
                    if (!Responsive.isMobile(context))
                      FilledButton.icon(
                        onPressed: () => showPartyForm(context, cubit, null),
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: Text(context.tr(customers
                            ? AppText.partiesNewCustomer
                            : AppText.partiesNewSupplier)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: KpiCard(
                        icon: Icons.call_received,
                        label: context.tr(AppText.partiesOwesUs),
                        value: Fmt.money(state.owedToUs),
                        tint: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: KpiCard(
                        icon: Icons.call_made,
                        label: context.tr(AppText.partiesWeOwe),
                        value: Fmt.money(state.weOwe),
                        tint: AppColors.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            onChanged: cubit.search,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: context.tr(AppText.search),
                              prefixIcon: const Icon(Icons.search, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilterChip(
                          label: Text(
                              context.tr(AppText.partiesOnlyWithBalance)),
                          selected: state.onlyWithBalance,
                          onSelected: cubit.filterWithBalance,
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
}

class _Table extends StatelessWidget {
  const _Table({required this.state, required this.cubit});

  final PartiesState state;
  final PartiesCubit cubit;

  @override
  Widget build(BuildContext context) {
    return AdminTable<Party>(
      rows: state.parties,
      onRowTap: (Party row) => showStatement(context, cubit, row),
      empty: EmptyState(
        icon: Icons.people_outline,
        message: context.tr(AppText.nothingYet),
      ),
      columns: <AdminColumn<Party>>[
        AdminColumn<Party>(
          label: context.tr(AppText.name),
          flex: 4,
          cell: (BuildContext context, Party row) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                row.name,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if ((row.phone ?? '').isNotEmpty)
                Text(row.phone!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        AdminColumn<Party>(
          label: context.tr(AppText.acctAccount),
          flex: 2,
          hideBelow: 1100,
          cell: (BuildContext context, Party row) => Text(
            row.accountCode ?? '—',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        AdminColumn<Party>(
          label: context.tr(AppText.partiesCreditLimit),
          flex: 2,
          alignEnd: true,
          hideBelow: 1300,
          cell: (BuildContext context, Party row) => Text(
            row.creditLimit.isZero ? '—' : Fmt.money(row.creditLimit),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        AdminColumn<Party>(
          label: context.tr(AppText.balance),
          flex: 3,
          alignEnd: true,
          cell: (BuildContext context, Party row) => _BalanceCell(party: row),
        ),
        AdminColumn<Party>(
          label: context.tr(AppText.actions),
          flex: 2,
          alignEnd: true,
          cell: (BuildContext context, Party row) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: context.tr(AppText.partiesSettle),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
                onPressed: () => showSettlement(context, cubit, row),
              ),
              IconButton(
                tooltip: context.tr(AppText.edit),
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: () => showPartyForm(context, cubit, row),
              ),
              IconButton(
                tooltip: context.tr(AppText.delete),
                icon: const Icon(Icons.delete_outline, size: 19),
                color: AppColors.danger,
                onPressed: () async {
                  if (!await confirmDelete(context, what: row.name)) return;
                  await cubit.remove(row.id);
                },
              ),
            ],
          ),
        ),
      ],
      mobileCard: (BuildContext context, Party row) => AdminRecordCard(
        onTap: () => showStatement(context, cubit, row),
        title: row.name,
        subtitle: row.phone,
        trailing: _BalanceCell(party: row),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => showSettlement(context, cubit, row),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: Text(context.tr(AppText.partiesSettle)),
          ),
          TextButton.icon(
            onPressed: () => showPartyForm(context, cubit, row),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.tr(AppText.edit)),
          ),
        ],
      ),
    );
  }
}

class _BalanceCell extends StatelessWidget {
  const _BalanceCell({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    if (party.balance.isZero) {
      return StatusChip.neutral(context, '—');
    }
    final bool over = party.wouldExceedLimit(Money.zero);
    return StatusChip(
      compact: true,
      label: Fmt.money(party.balance.abs),
      color: over
          ? AppColors.danger
          : party.owesUs
              ? AppColors.warning
              : AppColors.info,
      icon: party.owesUs ? Icons.call_received : Icons.call_made,
    );
  }
}
