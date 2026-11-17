import '../../../../core/classes/enums.dart';
import '../../../../core/money/money.dart';

/// One account in the chart.
class Account {
  const Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.normalSide,
    required this.isGroup,
    required this.isActive,
    this.parentId,
    this.systemKey,
    this.balance = Money.zero,
    this.debit = Money.zero,
    this.credit = Money.zero,
    this.note,
  });

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: (m['account_id'] ?? m['id']) as int,
        code: '${m['code']}',
        name: '${m['name']}',
        type: AccountType.fromDb(m['type']),
        normalSide: '${m['normal_side']}',
        isGroup: (m['is_group'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        parentId: m['parent_id'] as int?,
        systemKey: m['system_key'] as String?,
        balance: Money.fromDb(m['balance_minor']),
        debit: Money.fromDb(m['debit_minor']),
        credit: Money.fromDb(m['credit_minor']),
        note: m['note'] as String?,
      );

  final int id;
  final String code;
  final String name;
  final AccountType type;
  final String normalSide;
  final bool isGroup;
  final bool isActive;
  final int? parentId;

  /// The stable name the code uses to find this account — `cash`, `sales`,
  /// `cogs`. A posting never mentions an id, which is why re-coding the chart
  /// cannot break one.
  final String? systemKey;

  final Money balance;
  final Money debit;
  final Money credit;
  final String? note;

  String get label => '$code — $name';
}

/// A posted journal entry, as the list shows it.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.entryNo,
    required this.entryDate,
    required this.postedAt,
    required this.sourceType,
    required this.debit,
    required this.credit,
    required this.lineCount,
    this.memo,
    this.sourceId,
    this.userName,
    this.isVoid = false,
    this.reversalOfId,
  });

  factory JournalEntry.fromMap(Map<String, Object?> m) => JournalEntry(
        id: m['id'] as int,
        entryNo: '${m['entry_no']}',
        entryDate: '${m['entry_date']}',
        postedAt: '${m['posted_at']}',
        sourceType: '${m['source_type']}',
        debit: Money.fromDb(m['debit_minor']),
        credit: Money.fromDb(m['credit_minor']),
        lineCount: m['line_count'] as int? ?? 0,
        memo: m['memo'] as String?,
        sourceId: m['source_id'] as int?,
        userName: m['user_name'] as String?,
        isVoid: (m['is_void'] as int? ?? 0) == 1,
        reversalOfId: m['reversal_of_id'] as int?,
      );

  final int id;
  final String entryNo;
  final String entryDate;
  final String postedAt;
  final String sourceType;
  final Money debit;
  final Money credit;
  final int lineCount;
  final String? memo;
  final int? sourceId;
  final String? userName;
  final bool isVoid;
  final int? reversalOfId;

  bool get isManual => sourceType == 'manual';
  bool get isReversal => reversalOfId != null;
  bool get isBalanced => debit == credit;
}

/// One side of one posting, as the detail sheet shows it.
class JournalLineRow {
  const JournalLineRow({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.partyName,
    this.memo,
  });

  factory JournalLineRow.fromMap(Map<String, Object?> m) => JournalLineRow(
        accountId: m['account_id'] as int,
        accountCode: '${m['account_code'] ?? m['code'] ?? ''}',
        accountName: '${m['account_name'] ?? m['name'] ?? ''}',
        debit: Money.fromDb(m['debit_minor']),
        credit: Money.fromDb(m['credit_minor']),
        partyName: m['party_name'] as String?,
        memo: (m['line_memo'] ?? m['memo']) as String?,
      );

  final int accountId;
  final String accountCode;
  final String accountName;
  final Money debit;
  final Money credit;
  final String? partyName;
  final String? memo;
}

class JournalEntryDetail {
  const JournalEntryDetail({required this.entry, required this.lines});

  final JournalEntry entry;
  final List<JournalLineRow> lines;
}

/// A line of a voucher being typed in.
class VoucherLine {
  const VoucherLine({
    this.accountId,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.partyId,
    this.memo,
  });

  final int? accountId;
  final int debitMinor;
  final int creditMinor;
  final int? partyId;
  final String? memo;

  bool get isEmpty => accountId == null || (debitMinor == 0 && creditMinor == 0);

  VoucherLine copyWith({
    int? accountId,
    int? debitMinor,
    int? creditMinor,
    int? partyId,
    String? memo,
  }) =>
      VoucherLine(
        accountId: accountId ?? this.accountId,
        // Typing in one column clears the other: a line is a debit or a credit,
        // never both, and the schema refuses anything else.
        debitMinor: debitMinor ?? this.debitMinor,
        creditMinor: creditMinor ?? this.creditMinor,
        partyId: partyId ?? this.partyId,
        memo: memo ?? this.memo,
      );
}

/// One row of the trial balance.
class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    required this.debit,
    required this.credit,
  });

  factory TrialBalanceRow.fromMap(Map<String, Object?> m) => TrialBalanceRow(
        accountId: m['account_id'] as int,
        code: '${m['code']}',
        name: '${m['name']}',
        type: AccountType.fromDb(m['type']),
        debit: Money.fromDb(m['debit_balance_minor']),
        credit: Money.fromDb(m['credit_balance_minor']),
      );

  final int accountId;
  final String code;
  final String name;
  final AccountType type;
  final Money debit;
  final Money credit;
}

class TrialBalance {
  const TrialBalance({required this.rows, required this.asOf});

  final List<TrialBalanceRow> rows;
  final DateTime asOf;

  Money get totalDebit => Money(
        rows.fold(0, (int s, TrialBalanceRow r) => s + r.debit.minor),
      );

  Money get totalCredit => Money(
        rows.fold(0, (int s, TrialBalanceRow r) => s + r.credit.minor),
      );

  /// If this is ever anything but zero, something wrote to the journal without
  /// going through `Journal.post` — which refuses an unbalanced entry.
  Money get difference => Money(totalDebit.minor - totalCredit.minor);

  bool get isBalanced => difference.isZero;
}

/// One line of the income statement, already bucketed the way a person reads
/// it.
class IncomeLine {
  const IncomeLine({
    required this.bucket,
    required this.code,
    required this.name,
    required this.amount,
    this.systemKey,
  });

  factory IncomeLine.fromMap(Map<String, Object?> m) => IncomeLine(
        bucket: '${m['bucket']}',
        code: '${m['code']}',
        name: '${m['name']}',
        amount: Money.fromDb(m['amount_minor']),
        systemKey: m['system_key'] as String?,
      );

  /// `revenue`, `revenue_contra`, `cogs`, `expense`.
  final String bucket;

  final String code;
  final String name;
  final Money amount;
  final String? systemKey;
}

class IncomeStatement {
  const IncomeStatement({
    required this.lines,
    required this.from,
    required this.to,
  });

  final List<IncomeLine> lines;
  final DateTime from;
  final DateTime to;

  List<IncomeLine> get revenue => _of('revenue');
  List<IncomeLine> get contra => _of('revenue_contra');
  List<IncomeLine> get cogs => _of('cogs');
  List<IncomeLine> get expenses => _of('expense');

  List<IncomeLine> _of(String bucket) => lines
      .where((IncomeLine l) => l.bucket == bucket && !l.amount.isZero)
      .toList(growable: false);

  Money get grossRevenue => _sum('revenue');

  /// Returns and discounts sit in revenue accounts but reduce it, so they are
  /// shown on their own line and subtracted rather than buried.
  Money get returnsAndDiscounts => _sum('revenue_contra');

  Money get netRevenue =>
      Money(grossRevenue.minor - returnsAndDiscounts.minor);

  Money get costOfSales => _sum('cogs');

  Money get grossProfit => Money(netRevenue.minor - costOfSales.minor);

  Money get operatingExpenses => _sum('expense');

  Money get netProfit => Money(grossProfit.minor - operatingExpenses.minor);

  Money _sum(String bucket) => Money(
        lines
            .where((IncomeLine l) => l.bucket == bucket)
            .fold(0, (int s, IncomeLine l) => s + l.amount.minor),
      );
}

class BalanceSheet {
  const BalanceSheet({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.currentEarnings,
    required this.asOf,
  });

  final List<Account> assets;
  final List<Account> liabilities;
  final List<Account> equity;

  /// Profit for the period that has not been closed into retained earnings yet.
  /// Without it the sheet does not balance, and a balance sheet that does not
  /// balance is not one.
  final Money currentEarnings;

  final DateTime asOf;

  Money get totalAssets => _sum(assets);
  Money get totalLiabilities => _sum(liabilities);
  Money get totalEquity =>
      Money(_sum(equity).minor + currentEarnings.minor);

  Money get totalLiabilitiesAndEquity =>
      Money(totalLiabilities.minor + totalEquity.minor);

  Money get difference =>
      Money(totalAssets.minor - totalLiabilitiesAndEquity.minor);

  bool get isBalanced => difference.isZero;

  static Money _sum(List<Account> accounts) => Money(
        accounts.fold(0, (int s, Account a) => s + a.balance.minor),
      );
}

class LedgerRow {
  const LedgerRow({
    required this.entryId,
    required this.entryNo,
    required this.entryDate,
    required this.sourceType,
    required this.debit,
    required this.credit,
    required this.balance,
    this.memo,
    this.partyName,
  });

  final int entryId;
  final String entryNo;
  final String entryDate;
  final String sourceType;
  final Money debit;
  final Money credit;
  final Money balance;
  final String? memo;
  final String? partyName;
}
