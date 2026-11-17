import '../../../../core/error/guard.dart';
import '../entities/accounting_entities.dart';

abstract class AccountingRepository {
  Future<Result<List<Account>>> accounts({bool onlyActive = true});

  Future<Result<List<Account>>> postableAccounts();

  Future<Result<List<JournalEntry>>> entries({
    required DateTime from,
    required DateTime to,
    String? sourceType,
    String? search,
  });

  Future<Result<JournalEntryDetail>> entryDetail(int entryId);

  Future<Result<int>> postVoucher({
    required List<VoucherLine> lines,
    required DateTime date,
    String? memo,
    int? userId,
  });

  Future<Result<int>> reverseEntry(int entryId, {int? userId, String? memo});

  Future<Result<TrialBalance>> trialBalance({required DateTime asOf});

  Future<Result<IncomeStatement>> incomeStatement({
    required DateTime from,
    required DateTime to,
  });

  Future<Result<BalanceSheet>> balanceSheet({required DateTime asOf});

  Future<Result<List<LedgerRow>>> ledger({
    required int accountId,
    DateTime? from,
    DateTime? to,
  });

  Future<Result<List<String>>> missingSystemKeys();
}
