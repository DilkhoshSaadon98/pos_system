import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_detail.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_query.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_request.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/arithmetic.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/repositories/sales_repository.dart';

/// One line of the invoice being returned, with how much of it the cashier has
/// chosen to take back.
class ReturnDraftLine {
  const ReturnDraftLine({
    required this.line,
    required this.qtyMilli,
  });

  final SaleInvoiceLine line;
  final int qtyMilli;

  bool get isChosen => qtyMilli > 0;

  /// The refund for this line, in proportion to what was actually paid for it —
  /// discount included, so a customer who bought at 20 % off is refunded what
  /// they handed over rather than the list price.
  int get refundMinor =>
      mulDivRound(line.total.minor, qtyMilli, line.qtyMilli);

  int get discountShareMinor =>
      mulDivRound(line.discount.minor, qtyMilli, line.qtyMilli);

  int get costShareMinor =>
      mulDivRound(line.cost.minor, qtyMilli, line.qtyMilli);

  ReturnDraftLine copyWith({int? qtyMilli}) =>
      ReturnDraftLine(line: line, qtyMilli: qtyMilli ?? this.qtyMilli);
}

class SaleReturnState {
  const SaleReturnState({
    this.status = AppStatus.initial,
    this.invoice,
    this.lines = const <ReturnDraftLine>[],
    this.refundToCash = true,
    this.restock = true,
    this.reason,
    this.busy = false,
    this.failure,
    this.posted,
  });

  final AppStatus status;
  final SaleInvoice? invoice;
  final List<ReturnDraftLine> lines;
  final bool refundToCash;
  final bool restock;
  final String? reason;
  final bool busy;
  final Failure? failure;
  final PostedSale? posted;

  bool get hasChoice => lines.any((ReturnDraftLine l) => l.isChosen);

  int get refundMinor => lines.fold(
        0,
        (int sum, ReturnDraftLine l) => sum + (l.isChosen ? l.refundMinor : 0),
      );

  int get costMinor => lines.fold(
        0,
        (int sum, ReturnDraftLine l) =>
            sum + (l.isChosen ? l.costShareMinor : 0),
      );

  /// Refunding to account only makes sense when there is an account.
  bool get canRefundToAccount => invoice?.partyId != null;

  SaleReturnState copyWith({
    AppStatus? status,
    SaleInvoice? invoice,
    List<ReturnDraftLine>? lines,
    bool? refundToCash,
    bool? restock,
    String? reason,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    PostedSale? posted,
  }) =>
      SaleReturnState(
        status: status ?? this.status,
        invoice: invoice ?? this.invoice,
        lines: lines ?? this.lines,
        refundToCash: refundToCash ?? this.refundToCash,
        restock: restock ?? this.restock,
        reason: reason ?? this.reason,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
        posted: posted ?? this.posted,
      );
}

/// Giving goods back.
///
/// The screen never asks for a price: a return is worth exactly what the
/// customer paid for that line, discount and tax included, worked out from the
/// original invoice. Letting somebody type the refund is how a shop ends up
/// refunding the list price on a sale that was made at 30 % off.
class SaleReturnCubit extends Cubit<SaleReturnState> {
  SaleReturnCubit(this._repository) : super(const SaleReturnState());

  final SalesRepository _repository;

  /// Finding the invoice being returned.
  ///
  /// Returns only invoices that still have something on them: an invoice that
  /// has already been given back in full is not a candidate, and offering it
  /// only leads to the cashier discovering that at the end.
  Future<List<SaleInvoice>> findInvoices(String text) async {
    final DateTime now = DateTime.now();
    final Result<List<SaleInvoice>> result = await _repository.search(
      SalesQuery(
        from: DateTime(now.year - 1, now.month, now.day),
        to: now,
        search: text,
        docType: 'sale',
      ),
    );
    return result
        .valueOr(const <SaleInvoice>[])
        .where((SaleInvoice i) => !i.isVoid && !i.isFullyReturned)
        .take(40)
        .toList(growable: false);
  }

  void reset() => emit(const SaleReturnState());

  Future<void> loadInvoice(int invoiceId) async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<SaleInvoiceDetail> result = await _repository.detail(invoiceId);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    final SaleInvoiceDetail detail = result.valueOrNull!;
    emit(SaleReturnState(
      status: AppStatus.ready,
      invoice: detail.invoice,
      refundToCash: detail.invoice.partyId == null,
      lines: detail.lines
          .where((SaleInvoiceLine l) => l.returnableQtyMilli > 0)
          .map((SaleInvoiceLine l) => ReturnDraftLine(line: l, qtyMilli: 0))
          .toList(growable: false),
    ));
  }

  void setQty(int lineId, int qtyMilli) {
    emit(state.copyWith(
      lines: state.lines.map((ReturnDraftLine l) {
        if (l.line.id != lineId) return l;
        final int capped = qtyMilli < 0
            ? 0
            : (qtyMilli > l.line.returnableQtyMilli
                ? l.line.returnableQtyMilli
                : qtyMilli);
        return l.copyWith(qtyMilli: capped);
      }).toList(growable: false),
    ));
  }

  void selectAll() => emit(state.copyWith(
        lines: state.lines
            .map((ReturnDraftLine l) =>
                l.copyWith(qtyMilli: l.line.returnableQtyMilli))
            .toList(growable: false),
      ));

  void selectNone() => emit(state.copyWith(
        lines: state.lines
            .map((ReturnDraftLine l) => l.copyWith(qtyMilli: 0))
            .toList(growable: false),
      ));

  void setRefundToCash(bool value) => emit(state.copyWith(refundToCash: value));

  void setRestock(bool value) => emit(state.copyWith(restock: value));

  void setReason(String value) => emit(state.copyWith(reason: value));

  Future<PostedSale?> post({int? userId}) async {
    final SaleInvoice? invoice = state.invoice;
    if (invoice == null || !state.hasChoice) return null;

    emit(state.copyWith(busy: true, clearFailure: true));

    final SaleReturnRequest request = SaleReturnRequest(
      originInvoiceId: invoice.id,
      partyId: invoice.partyId,
      userId: userId,
      refundToCash: state.refundToCash,
      restock: state.restock,
      reason: state.reason,
      lines: <SaleReturnLine>[
        for (final ReturnDraftLine l in state.lines)
          if (l.isChosen)
            SaleReturnLine(
              originLineId: l.line.id,
              itemId: l.line.itemId,
              qtyMilli: l.qtyMilli,
              unitPriceMinor: l.line.unitPrice.minor,
              unitCostMinor: l.line.unitCost.minor,
              factorMilli: l.line.factorMilli,
              // The rate is recovered from what was actually charged rather
              // than read off the item, because the item's rate may have been
              // changed since the sale. `total - tax` is the taxable amount
              // whether prices were entered inclusive of tax or not, so one
              // formula serves both.
              taxRateBp: l.line.tax.isZero
                  ? 0
                  : mulDivRound(
                      l.line.tax.minor,
                      10000,
                      l.line.total.minor - l.line.tax.minor,
                    ),
              itemUnitId: l.line.itemUnitId,
              unitName: l.line.unitName,
              discountMinor: l.discountShareMinor,
            ),
      ],
    );

    final Result<PostedSale> result = await _repository.postReturn(request);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }

    emit(state.copyWith(busy: false, posted: result.valueOrNull));
    return result.valueOrNull;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
