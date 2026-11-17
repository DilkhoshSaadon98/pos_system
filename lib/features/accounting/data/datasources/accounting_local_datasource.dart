import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/accounting/journal.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/accounting_entities.dart';

/// The books.
///
/// Every figure on every report here is read from `journal_lines` through the
/// views, and every view resolves accounts by type or by `system_key` — never
/// by a hardcoded id. The old app's reports each carried their own copy of "7
/// is the cash account", which is why re-numbering the chart broke four screens
/// at once.
class AccountingLocalDataSource {
  AccountingLocalDataSource(this._database);

  final AppDatabase _database;

  // ------------------------------------------------------------- accounts --

  Future<List<Account>> accounts({bool onlyActive = true}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT a.*, IFNULL(b.balance_minor, 0) AS balance_minor,
             IFNULL(b.debit_minor, 0)  AS debit_minor,
             IFNULL(b.credit_minor, 0) AS credit_minor
        FROM accounts a
        LEFT JOIN v_account_balances b ON b.account_id = a.id
       ${onlyActive ? 'WHERE a.is_active = 1' : ''}
       ORDER BY a.code
      ''',
    );
    return rows.map(Account.fromMap).toList();
  }

  /// The accounts a hand-written voucher may touch: real ones, never a heading.
  Future<List<Account>> postableAccounts() async {
    final List<Account> all = await accounts();
    return all.where((Account a) => !a.isGroup).toList(growable: false);
  }

  // -------------------------------------------------------------- journal --

  Future<List<JournalEntry>> entries({
    required DateTime from,
    required DateTime to,
    String? sourceType,
    String? search,
    int limit = 500,
  }) async {
    final StringBuffer where = StringBuffer('e.entry_date BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[Time.dayOf(from), Time.dayOf(to)];

    if (sourceType != null) {
      where.write(' AND e.source_type = ?');
      args.add(sourceType);
    }
    final String q = (search ?? '').trim();
    if (q.isNotEmpty) {
      where.write(' AND (e.entry_no LIKE ? OR e.memo LIKE ?)');
      args
        ..add('%$q%')
        ..add('%$q%');
    }

    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT e.*,
             u.full_name AS user_name,
             IFNULL(SUM(l.debit_minor), 0)  AS debit_minor,
             IFNULL(SUM(l.credit_minor), 0) AS credit_minor,
             COUNT(l.id) AS line_count
        FROM journal_entries e
        LEFT JOIN journal_lines l ON l.entry_id = e.id
        LEFT JOIN users u         ON u.id = e.user_id
       WHERE ${where.toString()}
       GROUP BY e.id
       ORDER BY e.entry_date DESC, e.id DESC
       LIMIT ${limit.clamp(1, 5000)}
      ''',
      args,
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<JournalEntryDetail> entryDetail(int entryId) async {
    final List<Map<String, Object?>> head = await _database.db.rawQuery(
      '''
      SELECT e.*,
             u.full_name AS user_name,
             IFNULL(SUM(l.debit_minor), 0)  AS debit_minor,
             IFNULL(SUM(l.credit_minor), 0) AS credit_minor,
             COUNT(l.id) AS line_count
        FROM journal_entries e
        LEFT JOIN journal_lines l ON l.entry_id = e.id
        LEFT JOIN users u         ON u.id = e.user_id
       WHERE e.id = ?
       GROUP BY e.id
      ''',
      <Object?>[entryId],
    );
    if (head.isEmpty) {
      throw const AppFailure.notFound('That entry no longer exists.');
    }

    final List<Map<String, Object?>> lines = await _database.db.query(
      'v_general_ledger',
      where: 'entry_id = ?',
      whereArgs: <Object?>[entryId],
      orderBy: 'line_id',
    );

    return JournalEntryDetail(
      entry: JournalEntry.fromMap(head.first),
      lines: lines.map(JournalLineRow.fromMap).toList(),
    );
  }

  /// Posts a voucher a person typed.
  ///
  /// The balance check lives in `Journal.post` and is not repeated here: there
  /// is one door into the journal and it refuses an unbalanced entry, which is
  /// what makes `v_unbalanced_entries` reliably empty.
  Future<int> postVoucher({
    required List<VoucherLine> lines,
    required DateTime date,
    String? memo,
    int? userId,
  }) async {
    final List<VoucherLine> real =
        lines.where((VoucherLine l) => !l.isEmpty).toList(growable: false);
    if (real.length < 2) {
      throw const AppFailure.validation(
        'A voucher needs at least one debit and one credit.',
      );
    }

    return _database.transaction<int>((Transaction txn) async {
      final int entryId = await Journal.post(
        txn,
        sourceType: 'manual',
        entryDate: Time.dayOf(date),
        memo: memo,
        userId: userId,
        lines: <JournalLine>[
          for (final VoucherLine l in real)
            if (l.debitMinor > 0)
              JournalLine.debit(
                l.accountId!,
                l.debitMinor,
                partyId: l.partyId,
                memo: l.memo,
              )
            else
              JournalLine.credit(
                l.accountId!,
                l.creditMinor,
                partyId: l.partyId,
                memo: l.memo,
              ),
        ],
      );

      await Audit.write(
        txn,
        action: Audit.voucher,
        entity: 'journal_entry',
        entityId: entryId,
        userId: userId,
        detail: memo ?? '${real.length} lines',
      );

      return entryId;
    });
  }

  /// Reverses an entry by posting its mirror image.
  ///
  /// Both entries stay visible and both stay counted: the original plus its
  /// mirror sum to zero, so balances are correct while the ledger still shows
  /// what happened and when it was undone. Nothing is ever deleted — the old
  /// app deleted the transactions of an edited invoice and left the stock
  /// movements behind.
  Future<int> reverseEntry(int entryId, {int? userId, String? memo}) async {
    return _database.transaction<int>((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        'journal_entries',
        columns: <String>['id', 'source_type', 'reversal_of_id'],
        where: 'reversal_of_id = ?',
        whereArgs: <Object?>[entryId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const AppFailure.conflict(
          'That entry has already been reversed.',
        );
      }
      return Journal.reverse(txn, entryId, userId: userId, memo: memo);
    });
  }

  // ------------------------------------------------------------- reports ---

  /// The trial balance as it stood at the end of [asOf].
  ///
  /// Computed from the ledger with a date filter rather than read from
  /// `v_trial_balance`, because that view has no notion of a cut-off and a
  /// report someone runs for last month has to exclude this month.
  Future<TrialBalance> trialBalance({required DateTime asOf}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT a.id AS account_id, a.code, a.name, a.type, a.normal_side,
             IFNULL(SUM(l.debit_minor), 0)  AS debit_minor,
             IFNULL(SUM(l.credit_minor), 0) AS credit_minor
        FROM accounts a
        LEFT JOIN journal_lines l   ON l.account_id = a.id
        LEFT JOIN journal_entries e ON e.id = l.entry_id
                                   AND e.is_void = 0
                                   AND e.entry_date <= ?
       WHERE a.is_group = 0
       GROUP BY a.id
       HAVING debit_minor <> 0 OR credit_minor <> 0
       ORDER BY a.code
      ''',
      <Object?>[Time.dayOf(asOf)],
    );

    return TrialBalance(
      asOf: asOf,
      rows: rows.map((Map<String, Object?> m) {
        final int debit = m['debit_minor'] as int? ?? 0;
        final int credit = m['credit_minor'] as int? ?? 0;
        final int net = debit - credit;
        return TrialBalanceRow(
          accountId: m['account_id'] as int,
          code: '${m['code']}',
          name: '${m['name']}',
          type: AccountType.fromDb(m['type']),
          // An account shows in exactly one column: the side its balance is on.
          debit: Money(net > 0 ? net : 0),
          credit: Money(net < 0 ? -net : 0),
        );
      }).toList(),
    );
  }

  Future<IncomeStatement> incomeStatement({
    required DateTime from,
    required DateTime to,
  }) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT CASE
               WHEN a.type = 'revenue'
                    AND a.system_key IN ('sales_returns','sales_discounts')
                 THEN 'revenue_contra'
               WHEN a.type = 'revenue' THEN 'revenue'
               WHEN a.system_key IN ('cogs','shrinkage','gifts') THEN 'cogs'
               ELSE 'expense'
             END AS bucket,
             a.code, a.name, a.system_key,
             -- Every bucket reports a positive figure, so the statement reads
             -- the way it is spoken: revenue, less returns and discounts, less
             -- cost of sales, less expenses. Returns and discounts live in
             -- revenue accounts but carry debit balances, so they need the
             -- other subtraction — reporting them as negative revenue and then
             -- subtracting would add them back on.
             CASE WHEN a.type = 'revenue'
                       AND a.system_key NOT IN ('sales_returns','sales_discounts')
                  THEN IFNULL(SUM(l.credit_minor), 0) - IFNULL(SUM(l.debit_minor), 0)
                  ELSE IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0)
             END AS amount_minor
        FROM accounts a
        LEFT JOIN journal_lines l   ON l.account_id = a.id
        LEFT JOIN journal_entries e ON e.id = l.entry_id
                                   AND e.is_void = 0
                                   AND e.entry_date BETWEEN ? AND ?
       WHERE a.type IN ('revenue','expense') AND a.is_group = 0
       GROUP BY a.id
       ORDER BY bucket, a.code
      ''',
      <Object?>[Time.dayOf(from), Time.dayOf(to)],
    );

    return IncomeStatement(
      from: from,
      to: to,
      lines: rows.map(IncomeLine.fromMap).toList(),
    );
  }

  Future<BalanceSheet> balanceSheet({required DateTime asOf}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT a.id, a.code, a.name, a.type, a.normal_side, a.system_key,
             a.parent_id, a.is_group, a.is_active,
             CASE WHEN a.normal_side = 'debit'
                  THEN IFNULL(SUM(l.debit_minor), 0) - IFNULL(SUM(l.credit_minor), 0)
                  ELSE IFNULL(SUM(l.credit_minor), 0) - IFNULL(SUM(l.debit_minor), 0)
             END AS balance_minor
        FROM accounts a
        LEFT JOIN journal_lines l   ON l.account_id = a.id
        LEFT JOIN journal_entries e ON e.id = l.entry_id
                                   AND e.is_void = 0
                                   AND e.entry_date <= ?
       WHERE a.type IN ('asset','liability','equity') AND a.is_group = 0
       GROUP BY a.id
       ORDER BY a.code
      ''',
      <Object?>[Time.dayOf(asOf)],
    );

    final List<Account> all = rows
        .map(Account.fromMap)
        .where((Account a) => !a.balance.isZero)
        .toList(growable: false);

    // Revenue less expenses for everything up to the cut-off. This is the piece
    // that makes the sheet balance before a year-end close has been run — and a
    // shop that has never run one is the normal case.
    final List<Map<String, Object?>> earnings = await _database.db.rawQuery(
      '''
      SELECT IFNULL(SUM(CASE WHEN a.type = 'revenue'
                             THEN l.credit_minor - l.debit_minor
                             ELSE l.debit_minor - l.credit_minor END), 0) AS net
        FROM journal_lines l
        JOIN accounts a        ON a.id = l.account_id
        JOIN journal_entries e ON e.id = l.entry_id AND e.is_void = 0
       WHERE a.type IN ('revenue','expense') AND e.entry_date <= ?
      ''',
      <Object?>[Time.dayOf(asOf)],
    );

    // Revenue is a credit and expense a debit, so the expression above already
    // has the right sign for a credit-side equity figure.
    final int net = (earnings.first['net'] as num?)?.toInt() ?? 0;

    return BalanceSheet(
      asOf: asOf,
      assets: all
          .where((Account a) => a.type == AccountType.asset)
          .toList(growable: false),
      liabilities: all
          .where((Account a) => a.type == AccountType.liability)
          .toList(growable: false),
      equity: all
          .where((Account a) => a.type == AccountType.equity)
          .toList(growable: false),
      currentEarnings: Money(net),
    );
  }

  /// Every posting against one account, with a running balance.
  Future<List<LedgerRow>> ledger({
    required int accountId,
    DateTime? from,
    DateTime? to,
  }) async {
    final StringBuffer where = StringBuffer('account_id = ?');
    final List<Object?> args = <Object?>[accountId];
    if (from != null) {
      where.write(' AND entry_date >= ?');
      args.add(Time.dayOf(from));
    }
    if (to != null) {
      where.write(' AND entry_date <= ?');
      args.add(Time.dayOf(to));
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_general_ledger',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'entry_date, entry_id, line_id',
    );

    final List<Map<String, Object?>> side = await _database.db.query(
      'accounts',
      columns: <String>['normal_side'],
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    final bool debitSide =
        side.isEmpty || '${side.first['normal_side']}' == 'debit';

    int running = 0;
    return rows.map((Map<String, Object?> m) {
      final int debit = m['debit_minor'] as int? ?? 0;
      final int credit = m['credit_minor'] as int? ?? 0;
      running += debitSide ? debit - credit : credit - debit;
      return LedgerRow(
        entryId: m['entry_id'] as int,
        entryNo: '${m['entry_no']}',
        entryDate: '${m['entry_date']}',
        sourceType: '${m['source_type']}',
        debit: Money(debit),
        credit: Money(credit),
        balance: Money(running),
        memo: (m['line_memo'] ?? m['entry_memo']) as String?,
        partyName: m['party_name'] as String?,
      );
    }).toList();
  }

  /// Should always be empty. Shown on the reports screen anyway, because an
  /// assertion nobody can see is an assertion nobody trusts.
  Future<List<Map<String, Object?>>> unbalancedEntries() =>
      _database.db.query('v_unbalanced_entries');

  /// The keys the postings resolve, so the settings screen can prove that the
  /// chart is wired up before a shop discovers it at the till.
  static const List<String> requiredKeys = <String>[
    AccountKeys.cash,
    AccountKeys.bank,
    AccountKeys.card,
    AccountKeys.receivable,
    AccountKeys.payable,
    AccountKeys.inventory,
    AccountKeys.taxPayable,
    AccountKeys.sales,
    AccountKeys.salesReturns,
    AccountKeys.salesDiscounts,
    AccountKeys.serviceRevenue,
    AccountKeys.rounding,
    AccountKeys.cogs,
    AccountKeys.shrinkage,
    AccountKeys.gifts,
    AccountKeys.openingEquity,
    // Added with the shift and the second currency. A shop upgrading from an
    // older database gets them from the v3 back-fill; if one is missing the
    // reports screen says so before a cashier meets the error at the close.
    AccountKeys.cashOverShort,
    AccountKeys.cashForeign,
    AccountKeys.fxDifference,
    AccountKeys.loyaltyRedeemed,
  ];

  Future<List<String>> missingSystemKeys() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'accounts',
      columns: <String>['system_key'],
      where: "system_key IS NOT NULL AND system_key <> ''",
    );
    final Set<String> present = rows
        .map((Map<String, Object?> r) => '${r['system_key']}')
        .toSet();
    return requiredKeys
        .where((String key) => !present.contains(key))
        .toList(growable: false);
  }
}
