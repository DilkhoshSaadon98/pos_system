import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_detail.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_tender.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../printing/domain/repositories/printing_repository.dart';
import '../cubit/sales_cubit.dart';

/// One invoice, in full: what was sold, what was paid, and what can still be
/// done to it.
Future<void> showInvoiceDetail(
  BuildContext context,
  SalesCubit cubit,
  int invoiceId,
) async {
  final SaleInvoiceDetail? detail = await cubit.detail(invoiceId);
  if (detail == null || !context.mounted) return;

  final bool canSeeMoney = context.read<AuthCubit>().state.user?.canSeeMoney ?? true;
  final bool canVoid = context.read<AuthCubit>().state.user?.canVoid ?? true;
  final int? userId = context.read<AuthCubit>().state.user?.id;

  await showAppModal<void>(
    context,
    width: 680,
    title: detail.invoice.invoiceNo,
    subtitle: Fmt.dateTime(detail.invoice.issuedAt),
    builder: (BuildContext modalContext) => _InvoiceBody(
      detail: detail,
      cubit: cubit,
      canSeeMoney: canSeeMoney,
      canVoid: canVoid,
      userId: userId,
    ),
  );
}

class _InvoiceBody extends StatelessWidget {
  const _InvoiceBody({
    required this.detail,
    required this.cubit,
    required this.canSeeMoney,
    required this.canVoid,
    required this.userId,
  });

  final SaleInvoiceDetail detail;
  final SalesCubit cubit;
  final bool canSeeMoney;
  final bool canVoid;
  final int? userId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SaleInvoice invoice = detail.invoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            if (invoice.isVoid)
              StatusChip(
                label: context.tr(AppText.voidLabel),
                color: AppColors.danger,
                filled: true,
              ),
            if (invoice.isReturn)
              StatusChip(
                label: context.tr(AppText.salesReturnTitle),
                color: AppColors.info,
              ),
            StatusChip.neutral(
              context,
              invoice.partyName ?? context.tr(AppText.posWalkIn),
              icon: Icons.person_outline,
            ),
            if (invoice.cashierName != null)
              StatusChip.neutral(
                context,
                invoice.cashierName!,
                icon: Icons.badge_outlined,
              ),
          ],
        ),
        const SizedBox(height: 18),

        // ---- lines ----------------------------------------------------------
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.surfaces.hairline),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < detail.lines.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, color: theme.surfaces.hairline),
                _LineRow(line: detail.lines[i], canSeeMoney: canSeeMoney),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ---- totals ---------------------------------------------------------
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaces.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              TotalRow(
                label: context.tr(AppText.subtotal),
                value: Fmt.money(invoice.total - invoice.tax),
              ),
              if (!invoice.discount.isZero)
                TotalRow(
                  label: context.tr(AppText.discount),
                  value: '−${Fmt.money(invoice.discount)}',
                  color: AppColors.warning,
                ),
              if (!invoice.tax.isZero)
                TotalRow(
                  label: context.tr(AppText.tax),
                  value: Fmt.money(invoice.tax),
                ),
              TotalRow(
                emphasis: true,
                label: context.tr(AppText.total),
                value: Fmt.money(invoice.total),
              ),
              const SizedBox(height: 6),
              for (final SaleTender t in detail.tenders)
                TotalRow(
                  label: context.tr(_tenderKey(t.method)),
                  value: Fmt.money(t.amount),
                  icon: _tenderIcon(t.method),
                ),
              if (!invoice.due.isZero)
                TotalRow(
                  label: context.tr(AppText.due),
                  value: Fmt.money(invoice.due),
                  color: AppColors.warning,
                  emphasis: true,
                ),
              if (canSeeMoney) ...<Widget>[
                Divider(height: 20, color: theme.surfaces.hairline),
                TotalRow(
                  label: context.tr(AppText.cost),
                  value: Fmt.money(invoice.cost),
                ),
                TotalRow(
                  label: context.tr(AppText.profit),
                  value: Fmt.money(invoice.profit),
                  color: invoice.profit.isNegative
                      ? AppColors.danger
                      : AppColors.ok,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),

        Row(
          children: <Widget>[
            if (canVoid && !invoice.isVoid)
              TextButton.icon(
                onPressed: () => _void(context, invoice),
                icon: const Icon(Icons.block_outlined, size: 18),
                label: Text(context.tr(AppText.salesVoid)),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _print(context, invoice.id),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(context.tr(AppText.salesReprint)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr(AppText.close)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _void(BuildContext context, SaleInvoice invoice) async {
    final bool ok = await confirm(
      context,
      icon: Icons.block_outlined,
      title: context.tr(AppText.salesVoid),
      message: context.tr(AppText.salesVoidConfirm),
      confirmLabel: context.tr(AppText.salesVoid),
    );
    if (!ok || !context.mounted) return;

    final bool done = await cubit.voidSale(invoice.id, userId: userId);
    if (!context.mounted) return;
    if (done) {
      AppSnack.success(context, context.tr(AppText.salesVoided));
      Navigator.of(context).pop();
    } else {
      final String? detail = cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }

  Future<void> _print(BuildContext context, int invoiceId) async {
    final bool ok = await sl<PrintingRepository>()
        .printSale(invoiceId)
        .then((dynamic r) => r.isRight());
    if (!context.mounted) return;
    AppSnack.info(
      context,
      context.tr(ok ? AppText.printSent : AppText.printNoPrinter),
    );
  }

  static String _tenderKey(String method) => switch (method) {
        'card' => AppText.card,
        'bank' => AppText.bank,
        'credit' => AppText.credit,
        _ => AppText.cash,
      };

  static IconData _tenderIcon(String method) => switch (method) {
        'card' => Icons.credit_card,
        'bank' => Icons.account_balance_outlined,
        'credit' => Icons.schedule_outlined,
        _ => Icons.payments_outlined,
      };
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.canSeeMoney});

  final SaleInvoiceLine line;
  final bool canSeeMoney;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        line.itemName,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (line.isGift) ...<Widget>[
                      const SizedBox(width: 6),
                      StatusChip(
                        compact: true,
                        label: context.tr(AppText.posGift),
                        color: AppColors.accent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    '${Fmt.qtyMilli(line.qtyMilli)} ${line.unitName}',
                    '× ${Fmt.money(line.unitPrice)}',
                    if (!line.discount.isZero)
                      '−${Fmt.money(line.discount)}',
                    if (line.returnedQtyMilli > 0)
                      '${context.tr(AppText.salesAlreadyReturnedQty)} ${Fmt.qtyMilli(line.returnedQtyMilli)}',
                  ].join('   '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (canSeeMoney) ...<Widget>[
            SizedBox(
              width: 90,
              child: Text(
                Fmt.money(line.cost),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.merge(theme.tabular),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 110,
            child: Text(
              Fmt.money(line.total),
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
