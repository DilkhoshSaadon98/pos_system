import 'dart:async';

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
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/purchase_document.dart';
import '../cubit/purchase_return_cubit.dart';

/// Sending goods back to a supplier.
///
/// The credit is not typed either: it is the landed cost of what is going
/// back — what the shop actually paid for those goods once the discount and the
/// freight were spread over the delivery.
class PurchaseReturnPage extends StatelessWidget {
  const PurchaseReturnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PurchaseReturnCubit, PurchaseReturnState>(
      listenWhen: (PurchaseReturnState a, PurchaseReturnState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, PurchaseReturnState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PurchaseReturnCubit>().clearFailure();
      },
      builder: (BuildContext context, PurchaseReturnState state) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Responsive.isMobile(context) ? 14 : 24,
            20,
            Responsive.isMobile(context) ? 14 : 24,
            40,
          ),
          children: <Widget>[
            SectionHeader(
              title: context.tr(AppText.purchaseReturnTitle),
              subtitle: state.invoice == null
                  ? context.tr(AppText.salesPickInvoice)
                  : '${state.invoice!.invoiceNo}  ·  ${state.invoice!.partyName ?? ''}',
              actions: <Widget>[
                if (state.invoice != null)
                  OutlinedButton.icon(
                    onPressed: context.read<PurchaseReturnCubit>().reset,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(context.tr(AppText.salesPickInvoice)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (state.invoice == null)
              const _Finder()
            else if (state.status.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              _Form(state: state),
          ],
        );
      },
    );
  }
}

class _Finder extends StatefulWidget {
  const _Finder();

  @override
  State<_Finder> createState() => _FinderState();
}

class _FinderState extends State<_Finder> {
  Timer? _debounce;
  List<PurchaseInvoice> _results = const <PurchaseInvoice>[];
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
    final List<PurchaseInvoice> found =
        await context.read<PurchaseReturnCubit>().findInvoices(text);
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
              for (final PurchaseInvoice invoice in _results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context
                          .read<PurchaseReturnCubit>()
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
                                    '${Fmt.dateTime(invoice.issuedAt)}  ·  ${invoice.partyName ?? ''}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
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

class _Form extends StatelessWidget {
  const _Form({required this.state});

  final PurchaseReturnState state;

  @override
  Widget build(BuildContext context) {
    final PurchaseReturnCubit cubit = context.read<PurchaseReturnCubit>();
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
              for (final PurchaseReturnDraftLine line in state.lines) ...<Widget>[
                Divider(height: 1, color: theme.surfaces.hairline),
                _LineRow(
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
                      value: false,
                      icon: const Icon(Icons.account_balance_wallet_outlined,
                          size: 18),
                      label: Text(context.tr(AppText.partiesWeOwe)),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(context.tr(AppText.salesRefundCash)),
                    ),
                  ],
                  selected: <bool>{state.refundToCash},
                  onSelectionChanged: (Set<bool> s) =>
                      cubit.setRefundToCash(s.first),
                ),
                const SizedBox(height: 12),
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
                  label: context.tr(AppText.purchaseLandedCost),
                  value: Fmt.moneyMinor(state.creditMinor),
                  color: AppColors.info,
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
                        : const Icon(Icons.undo),
                    label: Text(context.tr(AppText.purchaseReturnNew)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _post(BuildContext context, PurchaseReturnCubit cubit) async {
    final int? userId = context.read<AuthCubit>().state.user?.id;
    final PostedPurchase? posted = await cubit.post(userId: userId);
    if (!context.mounted || posted == null) return;

    AppSnack.success(
      context,
      '${context.tr(AppText.salesReturnSaved)} — ${posted.invoiceNo}',
    );
    cubit.reset();
  }
}

class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PurchaseReturnDraftLine draft;
  final ValueChanged<int> onChanged;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final TextEditingController _qty =
      TextEditingController(text: Fmt.qtyMilli(widget.draft.qtyMilli));

  @override
  void didUpdateWidget(covariant _LineRow old) {
    super.didUpdateWidget(old);
    final String shown = Fmt.qtyMilli(widget.draft.qtyMilli);
    if (Fmt.parseQty(_qty.text)?.milli != widget.draft.qtyMilli) {
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
    final PurchaseInvoiceLine line = widget.draft.line;

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
                Text(
                  '${Fmt.qtyMilli(line.returnableQtyMilli)} ${line.unitName}'
                  '  ·  ${context.tr(AppText.purchaseLandedCost)} ${Fmt.money(line.landedUnitCost)}',
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
                  ? Fmt.moneyMinor(widget.draft.creditMinor)
                  : '—',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)
                  .merge(theme.tabular),
            ),
          ),
        ],
      ),
    );
  }
}
