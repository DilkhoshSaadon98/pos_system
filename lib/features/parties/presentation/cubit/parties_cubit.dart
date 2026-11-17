import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../data/datasources/parties_local_datasource.dart';
import '../../domain/entities/party.dart';
import '../../domain/repositories/parties_repository.dart';

class PartiesState {
  const PartiesState({
    this.status = AppStatus.initial,
    this.kind = PartyKind.customer,
    this.parties = const <Party>[],
    this.query = '',
    this.onlyWithBalance = false,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;

  /// Which side of the ledger this screen is showing. One screen serves both,
  /// because a customer and a supplier differ only in which parent account
  /// their sub-account hangs from.
  final PartyKind kind;

  final List<Party> parties;
  final String query;
  final bool onlyWithBalance;
  final bool busy;
  final Failure? failure;

  bool get isCustomers => kind == PartyKind.customer;

  Money get owedToUs => Money(parties.fold(
        0,
        (int sum, Party p) => sum + (p.balance.isPositive ? p.balance.minor : 0),
      ));

  Money get weOwe => Money(parties.fold(
        0,
        (int sum, Party p) => sum + (p.balance.isNegative ? -p.balance.minor : 0),
      ));

  PartiesState copyWith({
    AppStatus? status,
    PartyKind? kind,
    List<Party>? parties,
    String? query,
    bool? onlyWithBalance,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      PartiesState(
        status: status ?? this.status,
        kind: kind ?? this.kind,
        parties: parties ?? this.parties,
        query: query ?? this.query,
        onlyWithBalance: onlyWithBalance ?? this.onlyWithBalance,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Customers or suppliers, with what each of them owes or is owed.
class PartiesCubit extends Cubit<PartiesState> {
  PartiesCubit(this._repository, PartyKind kind)
      : super(PartiesState(kind: kind));

  final PartiesRepository _repository;
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
    final Result<List<Party>> result = await _repository.search(
      text: state.query,
      kind: state.kind,
      onlyWithBalance: state.onlyWithBalance,
    );
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            parties: result.valueOrNull,
            clearFailure: true,
          ));
  }

  void search(String text) {
    emit(state.copyWith(query: text));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 240), _run);
  }

  void filterWithBalance(bool only) {
    emit(state.copyWith(onlyWithBalance: only));
    _run();
  }

  Future<bool> save(PartySaveRequest request) =>
      _write(() => _repository.save(request));

  Future<bool> remove(int id) => _write(() => _repository.remove(id));

  Future<List<StatementRow>> statement(
    int partyId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final Result<List<StatementRow>> result =
        await _repository.statement(partyId, from: from, to: to);
    final Failure? failure = result.failureOrNull;
    if (failure != null && !isClosed) {
      emit(state.copyWith(failure: failure));
    }
    return result.valueOr(const <StatementRow>[]);
  }

  Future<List<OpenDocument>> openDocuments(int partyId) async {
    final Result<List<OpenDocument>> result = await _repository.openDocuments(
      partyId,
      isCustomer: state.isCustomers,
    );
    return result.valueOr(const <OpenDocument>[]);
  }

  /// Takes money in from a customer, or pays it out to a supplier, and applies
  /// it to the oldest unpaid invoices unless the screen said otherwise.
  Future<bool> settle({
    required int partyId,
    required Money amount,
    String methodKey = AccountKeys.cash,
    Money discount = Money.zero,
    int? userId,
    String? reference,
    String? note,
    bool allocateOldestFirst = true,
    List<PaymentAllocation>? allocations,
  }) async {
    List<PaymentAllocation> applied = allocations ?? const <PaymentAllocation>[];
    if (allocations == null && allocateOldestFirst) {
      final List<OpenDocument> open = await openDocuments(partyId);
      applied = PartiesLocalDataSource.allocateOldestFirst(amount, open);
    }

    return _write(() => _repository.settle(SettlementRequest(
          partyId: partyId,
          amount: amount,
          isReceipt: state.isCustomers,
          methodKey: methodKey,
          discount: discount,
          userId: userId,
          reference: reference,
          note: note,
          allocations: applied,
        )));
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));

  Future<bool> _write<T>(Future<Result<T>> Function() action) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<T> result = await action();
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
}
