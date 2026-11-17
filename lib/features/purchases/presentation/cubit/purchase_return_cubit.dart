import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/arithmetic.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/purchase_document.dart';
import '../../domain/repositories/purchases_repository.dart';

class PurchaseReturnDraftLine {
  const PurchaseReturnDraftLine({required this.line, required this.qtyMilli});

  final PurchaseInvoiceLine line;
  final int qtyMilli;

  bool get isChosen => qtyMilli > 0;

  /// The credit for this line: the landed cost of what is going back, which is
  /// what the shop actually paid for it once the discount and the freight were
  /// spread.
  int get creditMinor => mulDivRound(
        line.landedUnitCost.minor,
        (qtyMilli * line.factorMilli) ~/ 1000,
        1000,
      );

  PurchaseReturnDraftLine copyWith({int? qtyMilli}) =>
      PurchaseReturnDraftLine(line: line, qtyMilli: qtyMilli ?? this.qtyMilli);
}

class PurchaseReturnState {
  const PurchaseReturnState({
    this.status = AppStatus.initial,
    this.invoice,
    this.lines = const <PurchaseReturnDraftLine>[],
    this.refundToCash = false,
    this.reason,
    this.busy = false,
    this.failure,
    this.posted,
  });

  final AppStatus status;
  final PurchaseInvoice? invoice;
  final List<PurchaseReturnDraftLine> lines;

  /// Money back from the supplier, or — far more often — a reduction of what
  /// the shop still owes them.
  final bool refundToCash;

  final String? reason;
  final bool busy;
  final Failure? failure;
  final PostedPurchase? posted;

  bool get hasChoice =>
      lines.any((PurchaseReturnDraftLine l) => l.isChosen);

  int get creditMinor => lines.fold(
        0,
        (int sum, PurchaseReturnDraftLine l) =>
            sum + (l.isChosen ? l.creditMinor : 0),
      );

  PurchaseReturnState copyWith({
    AppStatus? status,
    PurchaseInvoice? invoice,
    List<PurchaseReturnDraftLine>? lines,
    bool? refundToCash,
    String? reason,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    PostedPurchase? posted,
  }) =>
      PurchaseReturnState(
        status: status ?? this.status,
        invoice: invoice ?? this.invoice,
        lines: lines ?? this.lines,
        refundToCash: refundToCash ?? this.refundToCash,
        reason: reason ?? this.reason,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
        posted: posted ?? this.posted,
      );
}

class PurchaseReturnCubit extends Cubit<PurchaseReturnState> {
  PurchaseReturnCubit(this._repository) : super(const PurchaseReturnState());

  final PurchasesRepository _repository;

  Future<List<PurchaseInvoice>> findInvoices(String text) async {
    final DateTime now = DateTime.now();
    final Result<List<PurchaseInvoice>> result = await _repository.search(
      PurchasesQuery(
        from: DateTime(now.year - 1, now.month, now.day),
        to: now,
        search: text,
        docType: 'purchase',
      ),
    );
    return result
        .valueOr(const <PurchaseInvoice>[])
        .where((PurchaseInvoice i) => !i.isVoid && !i.isFullyReturned)
        .take(40)
        .toList(growable: false);
  }

  void reset() => emit(const PurchaseReturnState());

  Future<void> loadInvoice(int invoiceId) async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<PurchaseInvoiceDetail> result =
        await _repository.detail(invoiceId);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    final PurchaseInvoiceDetail detail = result.valueOrNull!;
    emit(PurchaseReturnState(
      status: AppStatus.ready,
      invoice: detail.invoice,
      // Default to crediting the account: the shop most often still owes this
      // supplier, and reducing the debt is one entry rather than two.
      refundToCash: detail.invoice.due.isZero,
      lines: detail.lines
          .where((PurchaseInvoiceLine l) => l.returnableQtyMilli > 0)
          .map((PurchaseInvoiceLine l) =>
              PurchaseReturnDraftLine(line: l, qtyMilli: 0))
          .toList(growable: false),
    ));
  }

  void setQty(int lineId, int qtyMilli) {
    emit(state.copyWith(
      lines: state.lines.map((PurchaseReturnDraftLine l) {
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
            .map((PurchaseReturnDraftLine l) =>
                l.copyWith(qtyMilli: l.line.returnableQtyMilli))
            .toList(growable: false),
      ));

  void selectNone() => emit(state.copyWith(
        lines: state.lines
            .map((PurchaseReturnDraftLine l) => l.copyWith(qtyMilli: 0))
            .toList(growable: false),
      ));

  void setRefundToCash(bool value) => emit(state.copyWith(refundToCash: value));

  void setReason(String value) => emit(state.copyWith(reason: value));

  Future<PostedPurchase?> post({int? userId}) async {
    final PurchaseInvoice? invoice = state.invoice;
    if (invoice?.partyId == null || !state.hasChoice) return null;

    emit(state.copyWith(busy: true, clearFailure: true));

    final Result<PostedPurchase> result =
        await _repository.postReturn(PurchaseReturnRequest(
      originInvoiceId: invoice!.id,
      partyId: invoice.partyId!,
      userId: userId,
      refundToCash: state.refundToCash,
      reason: state.reason,
      lines: <PurchaseReturnLine>[
        for (final PurchaseReturnDraftLine l in state.lines)
          if (l.isChosen)
            PurchaseReturnLine(
              originLineId: l.line.id,
              itemId: l.line.itemId,
              qtyMilli: l.qtyMilli,
              factorMilli: l.line.factorMilli,
              landedUnitCostMinor: l.line.landedUnitCost.minor,
              unitCostMinor: l.line.unitCost.minor,
              taxRateBp: l.line.tax.isZero || l.line.net.isZero
                  ? 0
                  : mulDivRound(l.line.tax.minor, 10000, l.line.net.minor),
              itemUnitId: l.line.itemUnitId,
              unitName: l.line.unitName,
            ),
      ],
    ));
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
