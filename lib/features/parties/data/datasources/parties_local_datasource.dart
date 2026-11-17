import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/accounting/journal.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/shifts/shift_service.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/party.dart';

/// Customers, suppliers and employees, and the money that moves between them
/// and the shop.
class PartiesLocalDataSource {
  PartiesLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<Party>> search({
    String? text,
    PartyKind? kind,
    bool onlyActive = true,
    bool onlyWithBalance = false,
    int limit = 300,
  }) async {
    final StringBuffer where = StringBuffer('1 = 1');
    final List<Object?> args = <Object?>[];

    if (kind != null) {
      where.write(" AND (b.kind = ? OR b.kind = 'both')");
      args.add(kind.dbValue);
    }
    if (onlyWithBalance) where.write(' AND b.balance_minor <> 0');
    if (onlyActive) where.write(' AND p.is_active = 1');

    final String q = (text ?? '').trim();
    if (q.isNotEmpty) {
      where.write(' AND (b.name LIKE ? OR b.phone LIKE ? OR p.code LIKE ?)');
      args
        ..add('%$q%')
        ..add('%$q%')
        ..add('%$q%');
    }

    // The limit is a literal because SQLite will not take a parameter there,
    // and it is an integer this code chose — never anything a user typed.
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT b.*, p.address, p.email, p.note, p.is_active, p.credit_limit_minor,
             p.code, p.phone2, p.created_at
        FROM v_party_balances b
        JOIN parties p ON p.id = b.party_id
       WHERE ${where.toString()}
       ORDER BY b.name COLLATE NOCASE
       LIMIT ${limit.clamp(1, 5000)}
      ''',
      args,
    );
    return rows.map(Party.fromMap).toList();
  }

  Future<Party?> byId(int id) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT b.*, p.address, p.email, p.note, p.is_active, p.credit_limit_minor,
             p.code, p.phone2, p.created_at
        FROM v_party_balances b
        JOIN parties p ON p.id = b.party_id
       WHERE b.party_id = ?
      ''',
      <Object?>[id],
    );
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  Future<int> save(PartySaveRequest r) async {
    if (r.name.trim().isEmpty) {
      throw const AppFailure.validation('The account needs a name.');
    }

    final String stamp = Time.stamp();
    final Map<String, Object?> values = <String, Object?>{
      'name': r.name.trim(),
      'kind': r.kind.dbValue,
      'phone': _blankToNull(r.phone),
      'phone2': _blankToNull(r.phone2),
      'email': _blankToNull(r.email),
      'address': _blankToNull(r.address),
      'note': _blankToNull(r.note),
      'credit_limit_minor': r.creditLimit.minor,
      'is_active': r.isActive ? 1 : 0,
      'updated_at': stamp,
    };

    if (r.id == null) {
      values['created_at'] = stamp;
      return _database.db.insert('parties', values);
    }

    // Renaming a party renames its ledger account too, or the statement and the
    // chart of accounts start showing two different names for one person.
    await _database.transaction<void>((Transaction txn) async {
      await txn.update('parties', values,
          where: 'id = ?', whereArgs: <Object?>[r.id]);

      final List<Map<String, Object?>> rows = await txn.query(
        'parties',
        columns: <String>['account_id'],
        where: 'id = ?',
        whereArgs: <Object?>[r.id],
        limit: 1,
      );
      final int? accountId = rows.isEmpty ? null : rows.first['account_id'] as int?;
      if (accountId != null) {
        await txn.update(
          'accounts',
          <String, Object?>{'name': r.name.trim(), 'updated_at': stamp},
          where: 'id = ?',
          whereArgs: <Object?>[accountId],
        );
      }
    });
    return r.id!;
  }

  Future<void> remove(int id) async {
    final List<Map<String, Object?>> used = await _database.db.rawQuery(
      '''
      SELECT (SELECT COUNT(*) FROM sales_invoices    WHERE party_id = ?) AS sales,
             (SELECT COUNT(*) FROM purchase_invoices WHERE party_id = ?) AS buys,
             (SELECT COUNT(*) FROM payments          WHERE party_id = ?) AS pays
      ''',
      <Object?>[id, id, id],
    );
    final Map<String, Object?> c = used.first;
    final bool hasHistory = (c['sales'] as int) > 0 ||
        (c['buys'] as int) > 0 ||
        (c['pays'] as int) > 0;

    if (hasHistory) {
      await _database.db.update(
        'parties',
        <String, Object?>{'is_active': 0, 'updated_at': Time.stamp()},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return;
    }
    await _database.db.delete('parties', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// The account statement: every posting that touched this party's account,
  /// with a running balance.
  Future<List<StatementRow>> statement(
    int partyId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final Party? party = await byId(partyId);
    if (party == null || party.accountId == null) return const <StatementRow>[];

    final StringBuffer where = StringBuffer('account_id = ?');
    final List<Object?> args = <Object?>[party.accountId];
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

    int running = 0;
    return rows.map((Map<String, Object?> m) {
      final int debit = m['debit_minor'] as int? ?? 0;
      final int credit = m['credit_minor'] as int? ?? 0;
      running += debit - credit;
      return StatementRow(
        date: '${m['entry_date']}',
        entryNo: '${m['entry_no']}',
        sourceType: '${m['source_type']}',
        memo: '${m['line_memo'] ?? m['entry_memo'] ?? ''}',
        debit: Money(debit),
        credit: Money(credit),
        balance: Money(running),
      );
    }).toList();
  }

  Future<List<OpenDocument>> openDocuments(
    int partyId, {
    required bool isCustomer,
  }) async {
    final String table = isCustomer ? 'sales_invoices' : 'purchase_invoices';
    final List<Map<String, Object?>> rows = await _database.db.query(
      table,
      columns: <String>[
        'id',
        'invoice_no',
        'issued_at',
        'total_minor',
        'due_minor',
      ],
      where: "party_id = ? AND due_minor > 0 AND status <> 'void'",
      whereArgs: <Object?>[partyId],
      orderBy: 'issued_at',
    );
    return rows
        .map((Map<String, Object?> m) => OpenDocument(
              docType: isCustomer ? 'sale' : 'purchase',
              docId: m['id'] as int,
              number: '${m['invoice_no']}',
              issuedAt: '${m['issued_at']}',
              total: Money.fromDb(m['total_minor']),
              due: Money.fromDb(m['due_minor']),
            ))
        .toList();
  }

  /// Money received from a customer, or paid to a supplier.
  ///
  /// ```
  /// Receipt   Dr Cash / Bank          Cr Customer account
  ///           Dr Sales discounts      when a discount is allowed off the debt
  /// Payment   Dr Supplier account     Cr Cash / Bank
  ///                                   Cr Rounding, for a discount received
  /// ```
  Future<int> settle(SettlementRequest r) async {
    if (!r.amount.isPositive) {
      throw const AppFailure.validation('Enter an amount greater than zero.');
    }

    return _database.transaction<int>((Transaction txn) async {
      final String stamp = Time.stamp(r.at);
      final String no = await AppDatabase.nextDocumentNumber(
        txn,
        r.isReceipt ? 'receipt' : 'payment',
        at: r.at,
      );
      final int moneyAccount = await AppDatabase.accountIdIn(txn, r.methodKey);
      final int partyAccount = await ensureAccount(
        txn,
        r.partyId,
        r.isReceipt ? AccountKeys.receivable : AccountKeys.payable,
      );

      // Cash over the counter belongs to whichever drawer is open.
      final int? shiftId = await ShiftService.openShiftId(txn, userId: r.userId);

      final int paymentId = await txn.insert('payments', <String, Object?>{
        'payment_no': no,
        'shift_id': shiftId,
        'kind': r.isReceipt ? 'receipt' : 'payment',
        'party_id': r.partyId,
        'paid_at': stamp,
        'method': _methodName(r.methodKey),
        'account_id': moneyAccount,
        'counter_account_id': partyAccount,
        'amount_minor': r.amount.minor,
        'discount_minor': r.discount.minor,
        'user_id': r.userId,
        'reference': r.reference,
        'note': r.note,
        'created_at': stamp,
        'updated_at': stamp,
      });

      for (final PaymentAllocation a in r.allocations) {
        if (a.amount.minor <= 0) continue;
        await txn.insert('payment_allocations', <String, Object?>{
          'payment_id': paymentId,
          'doc_type': a.docType,
          'doc_id': a.docId,
          'amount_minor': a.amount.minor,
        });
        final String table =
            a.docType == 'sale' ? 'sales_invoices' : 'purchase_invoices';
        await txn.rawUpdate(
          '''
          UPDATE $table
             SET paid_minor = paid_minor + ?,
                 due_minor  = MAX(due_minor - ?, 0),
                 updated_at = ?
           WHERE id = ?
          ''',
          <Object?>[a.amount.minor, a.amount.minor, stamp, a.docId],
        );
      }

      final List<JournalLine> lines = r.isReceipt
          ? <JournalLine>[
              JournalLine.debit(moneyAccount, r.amount.minor, memo: no),
              if (r.discount.isPositive)
                JournalLine.debit(
                  await AppDatabase.accountIdIn(txn, AccountKeys.salesDiscounts),
                  r.discount.minor,
                  memo: no,
                ),
              JournalLine.credit(
                partyAccount,
                r.amount.minor + r.discount.minor,
                partyId: r.partyId,
                memo: no,
              ),
            ]
          : <JournalLine>[
              JournalLine.debit(
                partyAccount,
                r.amount.minor + r.discount.minor,
                partyId: r.partyId,
                memo: no,
              ),
              JournalLine.credit(moneyAccount, r.amount.minor, memo: no),
              if (r.discount.isPositive)
                JournalLine.credit(
                  await AppDatabase.accountIdIn(txn, AccountKeys.rounding),
                  r.discount.minor,
                  memo: 'Discount received $no',
                ),
            ];

      final int entryId = await Journal.post(
        txn,
        sourceType: r.isReceipt ? 'receipt' : 'payment',
        sourceId: paymentId,
        entryDate: stamp.substring(0, 10),
        memo: r.note ?? (r.isReceipt ? 'Receipt $no' : 'Payment $no'),
        userId: r.userId,
        shiftId: shiftId,
        lines: lines,
      );

      await txn.update(
        'payments',
        <String, Object?>{'journal_entry_id': entryId},
        where: 'id = ?',
        whereArgs: <Object?>[paymentId],
      );

      await Audit.write(
        txn,
        action: Audit.payment,
        entity: 'payment',
        entityId: paymentId,
        userId: r.userId,
        shiftId: shiftId,
        detail: '$no · ${r.amount.minor}',
      );

      return paymentId;
    });
  }

  /// Spreads a payment over the oldest open invoices first.
  static List<PaymentAllocation> allocateOldestFirst(
    Money amount,
    List<OpenDocument> open,
  ) {
    int left = amount.minor;
    final List<PaymentAllocation> out = <PaymentAllocation>[];
    for (final OpenDocument d in open) {
      if (left <= 0) break;
      final int take = d.due.minor < left ? d.due.minor : left;
      out.add(PaymentAllocation(
        docType: d.docType,
        docId: d.docId,
        amount: Money(take),
      ));
      left -= take;
    }
    return out;
  }

  static String _methodName(String key) => switch (key) {
        AccountKeys.bank => 'bank',
        AccountKeys.card => 'card',
        _ => 'cash',
      };

  static String? _blankToNull(String? v) {
    final String t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  /// A party's own sub-account under receivables or payables, created the first
  /// time it is needed — so every customer and supplier has a real ledger.
  static Future<int> ensureAccount(
    DatabaseExecutor db,
    int partyId,
    String parentKey,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'parties',
      columns: <String>['account_id', 'name'],
      where: 'id = ?',
      whereArgs: <Object?>[partyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AppFailure.notFound('Account $partyId no longer exists.');
    }
    final int? existing = rows.first['account_id'] as int?;
    if (existing != null) return existing;

    final int parentId = await AppDatabase.accountIdIn(db, parentKey);
    final List<Map<String, Object?>> parent = await db.query(
      'accounts',
      columns: <String>['code', 'type', 'normal_side'],
      where: 'id = ?',
      whereArgs: <Object?>[parentId],
      limit: 1,
    );
    final String stamp = Time.stamp();
    final int accountId = await db.insert('accounts', <String, Object?>{
      'code': '${parent.first['code']}-${partyId.toString().padLeft(4, '0')}',
      'name': '${rows.first['name']}',
      'type': parent.first['type'],
      'normal_side': parent.first['normal_side'],
      'parent_id': parentId,
      'is_group': 0,
      'is_active': 1,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.update(
      'parties',
      <String, Object?>{'account_id': accountId, 'updated_at': stamp},
      where: 'id = ?',
      whereArgs: <Object?>[partyId],
    );
    return accountId;
  }
}
