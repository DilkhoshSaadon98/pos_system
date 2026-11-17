import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/accounting_entities.dart';
import '../../domain/repositories/accounting_repository.dart';

class JournalState {
  JournalState({
    this.status = AppStatus.initial,
    this.entries = const <JournalEntry>[],
    this.accounts = const <Account>[],
    DateTime? from,
    DateTime? to,
    this.sourceType,
    this.search = '',
    this.busy = false,
    this.failure,
  })  : from = from ?? DateTime(DateTime.now().year, DateTime.now().month),
        to = to ?? DateTime.now();

  final AppStatus status;
  final List<JournalEntry> entries;

  /// Loaded alongside the list because the voucher editor needs them, and a
  /// chart of accounts is small enough to keep in memory.
  final List<Account> accounts;

  final DateTime from;
  final DateTime to;
  final String? sourceType;
  final String search;
  final bool busy;
  final Failure? failure;

  JournalState copyWith({
    AppStatus? status,
    List<JournalEntry>? entries,
    List<Account>? accounts,
    DateTime? from,
    DateTime? to,
    String? sourceType,
    bool clearSourceType = false,
    String? search,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      JournalState(
        status: status ?? this.status,
        entries: entries ?? this.entries,
        accounts: accounts ?? this.accounts,
        from: from ?? this.from,
        to: to ?? this.to,
        sourceType:
            clearSourceType ? null : (sourceType ?? this.sourceType),
        search: search ?? this.search,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class JournalCubit extends Cubit<JournalState> {
  JournalCubit(this._repository) : super(JournalState());

  final AccountingRepository _repository;
  Timer? _debounce;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));

    final Result<List<Account>> accounts = await _repository.postableAccounts();
    if (isClosed) return;
    emit(state.copyWith(accounts: accounts.valueOr(const <Account>[])));
    await _run();
  }

  Future<void> _run() async {
    final Result<List<JournalEntry>> result = await _repository.entries(
      from: state.from,
      to: state.to,
      sourceType: state.sourceType,
      search: state.search,
    );
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            entries: result.valueOrNull,
            clearFailure: true,
          ));
  }

  void setRange(DateTime from, DateTime to) {
    emit(state.copyWith(from: from, to: to));
    _run();
  }

  void filterSource(String? sourceType) {
    emit(sourceType == null
        ? state.copyWith(clearSourceType: true)
        : state.copyWith(sourceType: sourceType));
    _run();
  }

  void search(String text) {
    emit(state.copyWith(search: text));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<JournalEntryDetail?> detail(int entryId) async {
    final Result<JournalEntryDetail> result =
        await _repository.entryDetail(entryId);
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      if (!isClosed) emit(state.copyWith(failure: failure));
      return null;
    }
    return result.valueOrNull;
  }

  Future<bool> postVoucher({
    required List<VoucherLine> lines,
    required DateTime date,
    String? memo,
    int? userId,
  }) =>
      _write(() => _repository.postVoucher(
            lines: lines,
            date: date,
            memo: memo,
            userId: userId,
          ));

  Future<bool> reverse(int entryId, {int? userId}) =>
      _write(() => _repository.reverseEntry(entryId, userId: userId));

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
