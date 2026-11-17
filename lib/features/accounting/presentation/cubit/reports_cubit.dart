import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/accounting_entities.dart';
import '../../domain/repositories/accounting_repository.dart';

/// Which of the three statements is on screen.
enum ReportTab { trialBalance, incomeStatement, balanceSheet }

class ReportsState {
  ReportsState({
    this.status = AppStatus.initial,
    this.tab = ReportTab.trialBalance,
    DateTime? from,
    DateTime? to,
    this.trialBalance,
    this.income,
    this.balanceSheet,
    this.missingKeys = const <String>[],
    this.failure,
  })  : from = from ?? DateTime(DateTime.now().year, 1),
        to = to ?? DateTime.now();

  final AppStatus status;
  final ReportTab tab;

  /// The income statement is for a period; the other two are as at a date. The
  /// screen keeps one range and uses [to] as the cut-off, so switching tabs
  /// never silently changes what is being looked at.
  final DateTime from;
  final DateTime to;

  final TrialBalance? trialBalance;
  final IncomeStatement? income;
  final BalanceSheet? balanceSheet;

  /// System keys the chart of accounts is missing. Anything in here means a
  /// posting will fail at the till, so it is shown at the top of the reports
  /// rather than discovered by a cashier.
  final List<String> missingKeys;

  final Failure? failure;

  ReportsState copyWith({
    AppStatus? status,
    ReportTab? tab,
    DateTime? from,
    DateTime? to,
    TrialBalance? trialBalance,
    IncomeStatement? income,
    BalanceSheet? balanceSheet,
    List<String>? missingKeys,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      ReportsState(
        status: status ?? this.status,
        tab: tab ?? this.tab,
        from: from ?? this.from,
        to: to ?? this.to,
        trialBalance: trialBalance ?? this.trialBalance,
        income: income ?? this.income,
        balanceSheet: balanceSheet ?? this.balanceSheet,
        missingKeys: missingKeys ?? this.missingKeys,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// The three statements, all read from the same ledger.
///
/// They are loaded together on purpose: an owner who looks at the profit for
/// the month immediately wants to know whether the balance sheet still
/// balances, and computing all three costs three queries on a database that
/// lives on the same machine.
class ReportsCubit extends Cubit<ReportsState> {
  ReportsCubit(this._repository) : super(ReportsState());

  final AccountingRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<TrialBalance> trial =
        await _repository.trialBalance(asOf: state.to);
    final Result<IncomeStatement> income =
        await _repository.incomeStatement(from: state.from, to: state.to);
    final Result<BalanceSheet> sheet =
        await _repository.balanceSheet(asOf: state.to);
    final Result<List<String>> missing = await _repository.missingSystemKeys();
    if (isClosed) return;

    final Failure? failure = firstFailure(<Result<Object?>>[
      trial,
      income,
      sheet,
    ]);
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    emit(state.copyWith(
      status: AppStatus.ready,
      trialBalance: trial.valueOrNull,
      income: income.valueOrNull,
      balanceSheet: sheet.valueOrNull,
      missingKeys: missing.valueOr(const <String>[]),
      clearFailure: true,
    ));
  }

  void setTab(ReportTab tab) => emit(state.copyWith(tab: tab));

  Future<void> setRange(DateTime from, DateTime to) async {
    emit(state.copyWith(from: from, to: to));
    await load();
  }
}
