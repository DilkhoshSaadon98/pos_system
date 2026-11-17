import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/purchase_document.dart';
import '../../domain/repositories/purchases_repository.dart';

class PurchasesState {
  PurchasesState({
    this.status = AppStatus.initial,
    PurchasesQuery? query,
    this.invoices = const <PurchaseInvoice>[],
    this.busy = false,
    this.failure,
  }) : query = query ?? _thisMonth();

  final AppStatus status;
  final PurchasesQuery query;
  final List<PurchaseInvoice> invoices;
  final bool busy;
  final Failure? failure;

  PurchasesSummary get summary => PurchasesSummary.of(invoices);

  static PurchasesQuery _thisMonth() {
    final DateTime now = DateTime.now();
    return PurchasesQuery(from: DateTime(now.year, now.month), to: now);
  }

  PurchasesState copyWith({
    AppStatus? status,
    PurchasesQuery? query,
    List<PurchaseInvoice>? invoices,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      PurchasesState(
        status: status ?? this.status,
        query: query ?? this.query,
        invoices: invoices ?? this.invoices,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class PurchasesCubit extends Cubit<PurchasesState> {
  PurchasesCubit(this._repository) : super(PurchasesState());

  final PurchasesRepository _repository;
  Timer? _debounce;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));
    await _run();
  }

  Future<void> _run() async {
    final Result<List<PurchaseInvoice>> result =
        await _repository.search(state.query);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            invoices: result.valueOrNull,
            clearFailure: true,
          ));
  }

  void setRange(DateTime from, DateTime to) {
    emit(state.copyWith(query: state.query.copyWith(from: from, to: to)));
    _run();
  }

  void search(String text) {
    emit(state.copyWith(query: state.query.copyWith(search: text)));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  void filterByDocType(String? docType) {
    emit(state.copyWith(
      query: docType == null
          ? state.query.copyWith(clearDocType: true)
          : state.query.copyWith(docType: docType),
    ));
    _run();
  }

  void filterUnpaid(bool only) {
    emit(state.copyWith(query: state.query.copyWith(onlyUnpaid: only)));
    _run();
  }

  Future<PurchaseInvoiceDetail?> detail(int invoiceId) async {
    final Result<PurchaseInvoiceDetail> result =
        await _repository.detail(invoiceId);
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      if (!isClosed) emit(state.copyWith(failure: failure));
      return null;
    }
    return result.valueOrNull;
  }

  Future<bool> voidPurchase(int invoiceId, {int? userId}) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result =
        await _repository.voidPurchase(invoiceId: invoiceId, userId: userId);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }
    await _run();
    if (!isClosed) emit(state.copyWith(busy: false));
    return true;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
