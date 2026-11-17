import 'dart:async';

import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
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
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/sale_return_cubit.dart';

/// Taking goods back, in two steps: find the invoice, then say what is coming
/// back and how it is being refunded.
///
/// The refund is never typed. It is worked out from the original line — its
/// price, its share of the discounts and its tax — because a shop that lets a
/// cashier type a refund figure eventually refunds the list price on a sale
/// that was made at thirty per cent off.
class SaleReturnPage extends StatelessWidget {
  const SaleReturnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SaleReturnCubit, SaleReturnState>(
      listenWhen: (SaleReturnState a, SaleReturnState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, SaleReturnState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<SaleReturnCubit>().clearFailure();
      },
      builder: (BuildContext context, SaleReturnState state) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Responsive.isMobile(context) ? 14 : 24,
            20,
            Responsive.isMobile(context) ? 14 : 24,
            40,
          ),
          children: <Widget>[
            SectionHeader(
              title: context.tr(AppText.salesReturnTitle),
              subtitle: state.invoice == null
                  ? context.tr(AppText.salesPickInvoice)
                  : '${state.invoice!.invoiceNo}  ·  ${Fmt.dateTime(state.invoice!.issuedAt)}',
              actions: <Widget>[
                if (state.invoice != null)
                  OutlinedButton.icon(
                    onPressed: context.read<SaleReturnCubit>().reset,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(context.tr(AppText.salesPickInvoice)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (state.invoice == null)
              const _InvoiceFinder()
            else if (state.status.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              _ReturnForm(state: state),
          ],
        );
      },
    );
  }
}

class _InvoiceFinder extends StatefulWidget {
  const _InvoiceFinder();

  @override
  State<_InvoiceFinder> createState() => _InvoiceFinderState();
}

class _InvoiceFinderState extends State<_InvoiceFinder> {
  Timer? _debounce;
  List<SaleInvoice> _results = const <SaleInvoice>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run(String text) async {
    setState(() => _loading = true);
    final List<SaleInvoice> found =
        await context.read<SaleReturnCubit>().findInvoices(text);
    if (!mounted) return;
    setState(() {
      _results = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              autofocus: true,
              onChanged: (String text) {
                _debounce?.cancel();
                _debounce =
                    Timer(const Duration(milliseconds: 250), () => _run(text));
              },
              decoration: InputDecoration(
                hintText: context.tr(AppText.salesPickInvoice),
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_results.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                message: context.tr(AppText.noResults),
              )
            else
              for (final SaleInvoice invoice in _results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context
                          .read<SaleReturnCubit>()
                          .loadInvoice(invoice.id),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.surfaces.hairline),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    invoice.invoiceNo,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${Fmt.dateTime(invoice.issuedAt)}  ·  '
                                    '${invoice.partyName ?? context.tr(AppText.posWalkIn)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (invoice.isPartlyReturned)
                              StatusChip(
                                compact: true,
                                label:
                                    context.tr(AppText.salesPartiallyReturned),
                                color: AppColors.warning,
                              ),
                            const SizedBox(width: 12),
                            Text(
                              Fmt.money(invoice.total),
                              style: theme.textTheme.bodyMedium
                                  ?.merge(theme.tabular),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReturnForm extends StatelessWidget {
  const _ReturnForm({required this.state});

  final SaleReturnState state;

  @override
  Widget build(BuildContext context) {
    final SaleReturnCubit cubit = context.read<SaleReturnCubit>();
    final ThemeData theme = Theme.of(context);

    if (state.lines.isEmpty) {
      return Card(
        child: EmptyState(
          icon: Icons.assignment_turned_in_outlined,
          message: context.tr(AppText.salesNothingToReturn),
          action: OutlinedButton(
            onPressed: cubit.reset,
            child: Text(context.tr(AppText.salesPickInvoice)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.tr(AppText.salesLines),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: cubit.selectAll,
                      child: Text(context.tr(AppText.all)),
                    ),
                    TextButton(
                      onPressed: cubit.selectNone,
                      child: Text(context.tr(AppText.clear)),
                    ),
                  ],
                ),
              ),
              for (final ReturnDraftLine line in state.lines) ...<Widget>[
                Divider(height: 1, color: theme.surfaces.hairline),
                _ReturnLineRow(
                  key: ValueKey<int>(line.line.id),
                  draft: line,
                  onChanged: (int qty) => cubit.setQty(line.line.id, qty),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr(AppText.salesRefundMethod),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(context.tr(AppText.salesRefundCash)),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      enabled: state.canRefundToAccount,
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 18),
                      label: Text(context.tr(AppText.salesRefundCredit)),
                    ),
                  ],
                  selected: <bool>{state.refundToCash},
                  onSelectionChanged: (Set<bool> s) =>
                      cubit.setRefundToCash(s.first),
                ),
                const SizedBox(height: 6),
                AppSwitchTile(
                  icon: Icons.inventory_2_outlined,
                  title: context.tr(AppText.salesRestock),
                  subtitle: context.tr(AppText.stockKindSaleReturn),
                  value: state.restock,
                  onChanged: cubit.setRestock,
                ),
                const SizedBox(height: 6),
                TextField(
                  onChanged: cubit.setReason,
                  decoration: InputDecoration(
                    labelText: context.tr(AppText.salesReturnReason),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                TotalRow(
                  emphasis: true,
                  label: context.tr(AppText.salesRefundMethod),
                  value: Fmt.moneyMinor(state.refundMinor),
                  color: AppColors.danger,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.busy || !state.hasChoice
                        ? null
                        : () => _post(context, cubit),
                    icon: state.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.assignment_return_outlined),
                    label: Text(context.tr(AppText.salesReturnNew)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _post(BuildContext context, SaleReturnCubit cubit) async {
    final int? userId = context.read<AuthCubit>().state.user?.id;
    final PostedSale? posted = await cubit.post(userId: userId);
    if (!context.mounted || posted == null) return;

    AppSnack.success(
      context,
      '${context.tr(AppText.salesReturnSaved)} — ${posted.invoiceNo}',
    );
    cubit.reset();
  }
}

class _ReturnLineRow extends StatefulWidget {
  const _ReturnLineRow({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final ReturnDraftLine draft;
  final ValueChanged<int> onChanged;

  @override
  State<_ReturnLineRow> createState() => _ReturnLineRowState();
}

class _ReturnLineRowState extends State<_ReturnLineRow> {
  late final TextEditingController _qty =
      TextEditingController(text: Fmt.qtyMilli(widget.draft.qtyMilli));

  @override
  void didUpdateWidget(covariant _ReturnLineRow old) {
    super.didUpdateWidget(old);
    // The "all" and "clear" buttons change the quantity from outside this row.
    final String shown = Fmt.qtyMilli(widget.draft.qtyMilli);
    if (_qty.text != shown && Fmt.parseQty(_qty.text)?.milli != widget.draft.qtyMilli) {
      _qty.text = shown;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SaleInvoiceLine line = widget.draft.line;

    return Container(
      color: widget.draft.isChosen ? theme.surfaces.overlay : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: widget.draft.isChosen,
            onChanged: (bool? v) {
              final int qty = (v ?? false) ? line.returnableQtyMilli : 0;
              _qty.text = Fmt.qtyMilli(qty);
              widget.onChanged(qty);
            },
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(line.itemName, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.qtyMilli(line.returnableQtyMilli)} ${line.unitName}'
                  '  ·  ${Fmt.money(line.unitPrice)}'
                  '${line.returnedQtyMilli > 0 ? '  ·  ${context.tr(AppText.salesAlreadyReturnedQty)} ${Fmt.qtyMilli(line.returnedQtyMilli)}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: context.tr(AppText.salesReturnQty),
              ),
              onChanged: (String v) {
                final Qty? q = Fmt.parseQty(v);
                widget.onChanged(q?.milli ?? 0);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              widget.draft.isChosen
                  ? Fmt.moneyMinor(widget.draft.refundMinor)
                  : '—',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.draft.isChosen ? AppColors.danger : null,
                  )
                  .merge(theme.tabular),
            ),
          ),
        ],
      ),
    );
  }
}
