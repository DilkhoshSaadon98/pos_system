import 'package:sqflite_common/sqlite_api.dart';

import '../database/app_database.dart';
import '../error/exceptions.dart';
import '../utils/time.dart';

//? A single line in a journal entry, which is either a debit or a credit.
class JournalLine {
  const JournalLine.debit(
    this.accountId,
    this.amountMinor, {
    this.partyId,
    this.memo,
  })  : isDebit = true,
        assert(amountMinor >= 0, 'A debit cannot be negative');

  const JournalLine.credit(
    this.accountId,
    this.amountMinor, {
    this.partyId,
    this.memo,
  })  : isDebit = false,
        assert(amountMinor >= 0, 'A credit cannot be negative');

  final int accountId;
  final int amountMinor;
  final bool isDebit;
  final int? partyId;
  final String? memo;

  int get debitMinor => isDebit ? amountMinor : 0;
  int get creditMinor => isDebit ? 0 : amountMinor;
}

//? A journal entry is a set of debits and credits that sum to zero, posted to the ledger.
class Journal {
  const Journal._();
//? Posts a journal entry to the ledger, returning its id. The lines must sum to zero.
  static Future<int> post(
    DatabaseExecutor db, {
    required String sourceType,
    required List<JournalLine> lines,
    int? sourceId,
    String? entryDate,
    String? memo,
    int? userId,
    int? reversalOfId,
    int? shiftId,
  }) async {
    final List<JournalLine> real = lines
        .where((JournalLine l) => l.amountMinor != 0)
        .toList(growable: false);

    if (real.length < 2) {
      throw const AppFailure.validation(
        'A journal entry needs at least one debit and one credit.',
      );
    }

    int debits = 0;
    int credits = 0;
    for (final JournalLine l in real) {
      debits += l.debitMinor;
      credits += l.creditMinor;
    }
    if (debits != credits) {
      throw AppFailure.validation(
        'Entry is out of balance by ${debits - credits} minor units '
        '(debits $debits, credits $credits).',
      );
    }

    final String stamp = Time.stamp();
    final String date = entryDate ?? stamp.substring(0, 10);
    final String entryNo =
        await AppDatabase.nextDocumentNumber(db, 'journal');

    final int entryId = await db.insert('journal_entries', <String, Object?>{
      'entry_no': entryNo,
      'entry_date': date,
      'posted_at': stamp,
      'source_type': sourceType,
      'source_id': sourceId,
      'memo': memo,
      'user_id': userId,
      'is_void': 0,
      'reversal_of_id': reversalOfId,
      'shift_id': shiftId,
    });

    int lineNo = 0;
    for (final JournalLine l in real) {
      await db.insert('journal_lines', <String, Object?>{
        'entry_id': entryId,
        'account_id': l.accountId,
        'party_id': l.partyId,
        'debit_minor': l.debitMinor,
        'credit_minor': l.creditMinor,
        'memo': l.memo,
        'line_no': lineNo++,
      });
    }

    return entryId;
  }

//? Reverses a journal entry by posting a mirror image of it, leaving both entries visible.
  static Future<int> reverse(
    DatabaseExecutor db,
    int entryId, {
    String? memo,
    int? userId,
    int? shiftId,
  }) async {
    final List<Map<String, Object?>> lines = await db.query(
      'journal_lines',
      where: 'entry_id = ?',
      whereArgs: <Object?>[entryId],
      orderBy: 'line_no',
    );
    if (lines.isEmpty) {
      throw const AppFailure.notFound('That journal entry no longer exists.');
    }

    final List<Map<String, Object?>> head = await db.query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: <Object?>[entryId],
      limit: 1,
    );
    final String sourceType = '${head.first['source_type']}';

    final List<JournalLine> mirrored = lines.map((Map<String, Object?> l) {
      final int debit = l['debit_minor'] as int? ?? 0;
      final int credit = l['credit_minor'] as int? ?? 0;
      final int accountId = l['account_id'] as int;
      final int? partyId = l['party_id'] as int?;
      return debit > 0
          ? JournalLine.credit(accountId, debit, partyId: partyId)
          : JournalLine.debit(accountId, credit, partyId: partyId);
    }).toList(growable: false);

    return post(
      db,
      sourceType: sourceType,
      sourceId: head.first['source_id'] as int?,
      memo: memo ?? 'Reversal of ${head.first['entry_no']}',
      userId: userId,
      reversalOfId: entryId,
      shiftId: shiftId,
      lines: mirrored,
    );
  }
}
