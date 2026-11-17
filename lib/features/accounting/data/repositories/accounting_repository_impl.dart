import '../../../../core/error/guard.dart';
import '../../domain/entities/accounting_entities.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../datasources/accounting_local_datasource.dart';

class AccountingRepositoryImpl implements AccountingRepository {
  const AccountingRepositoryImpl(this._local);

  final AccountingLocalDataSource _local;

  @override
  Future<Result<List<Account>>> accounts({bool onlyActive = true}) =>
      guard(() => _local.accounts(onlyActive: onlyActive));

  @override
  Future<Result<List<Account>>> postableAccounts() =>
      guard(_local.postableAccounts);

  @override
  Future<Result<List<JournalEntry>>> entries({
    required DateTime from,
    required DateTime to,
    String? sourceType,
    String? search,
  }) =>
      guard(() => _local.entries(
            from: from,
            to: to,
            sourceType: sourceType,
            search: search,
          ));

  @override
  Future<Result<JournalEntryDetail>> entryDetail(int entryId) =>
      guard(() => _local.entryDetail(entryId));

  @override
  Future<Result<int>> postVoucher({
    required List<VoucherLine> lines,
    required DateTime date,
    String? memo,
    int? userId,
  }) =>
      guard(() => _local.postVoucher(
            lines: lines,
            date: date,
            memo: memo,
            userId: userId,
          ));

  @override
  Future<Result<int>> reverseEntry(int entryId, {int? userId, String? memo}) =>
      guard(() => _local.reverseEntry(entryId, userId: userId, memo: memo));

  @override
  Future<Result<TrialBalance>> trialBalance({required DateTime asOf}) =>
      guard(() => _local.trialBalance(asOf: asOf));

  @override
  Future<Result<IncomeStatement>> incomeStatement({
    required DateTime from,
    required DateTime to,
  }) =>
      guard(() => _local.incomeStatement(from: from, to: to));

  @override
  Future<Result<BalanceSheet>> balanceSheet({required DateTime asOf}) =>
      guard(() => _local.balanceSheet(asOf: asOf));

  @override
  Future<Result<List<LedgerRow>>> ledger({
    required int accountId,
    DateTime? from,
    DateTime? to,
  }) =>
      guard(() => _local.ledger(accountId: accountId, from: from, to: to));

  @override
  Future<Result<List<String>>> missingSystemKeys() =>
      guard(_local.missingSystemKeys);
}
