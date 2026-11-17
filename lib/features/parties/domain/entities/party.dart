import '../../../../core/classes/enums.dart';
import '../../../../core/money/money.dart';

/// A customer, a supplier, both, or an employee.
///
/// One table for all of them: the old schema had `tbl_users` and `tbl_supplier`
/// holding the same columns, and half the reports only ever looked at one of
/// the two. A party owns a ledger account under receivables or payables,
/// created the moment it is first needed, so "how much does Ahmed owe" is a
/// question the general ledger can answer rather than a hand-written query over
/// invoices.
class Party {
  const Party({
    required this.id,
    required this.name,
    required this.kind,
    required this.balance,
    this.code,
    this.phone,
    this.phone2,
    this.email,
    this.address,
    this.note,
    this.accountId,
    this.accountCode,
    this.creditLimit = Money.zero,
    this.isActive = true,
  });

  factory Party.fromMap(Map<String, Object?> m) => Party(
        id: (m['party_id'] ?? m['id']) as int,
        name: '${m['name']}',
        kind: PartyKind.fromDb(m['kind']),
        balance: Money.fromDb(m['balance_minor']),
        code: m['code'] as String?,
        phone: m['phone'] as String?,
        phone2: m['phone2'] as String?,
        email: m['email'] as String?,
        address: m['address'] as String?,
        note: m['note'] as String?,
        accountId: m['account_id'] as int?,
        accountCode: m['account_code'] as String?,
        creditLimit: Money.fromDb(m['credit_limit_minor']),
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  final int id;
  final String name;
  final PartyKind kind;

  /// Positive means they owe us (a customer's debt); negative means we owe
  /// them. One sign convention, taken straight from the ledger.
  final Money balance;

  final String? code;
  final String? phone;
  final String? phone2;
  final String? email;
  final String? address;
  final String? note;
  final int? accountId;
  final String? accountCode;
  final Money creditLimit;
  final bool isActive;

  bool get isCustomer =>
      kind == PartyKind.customer || kind == PartyKind.both;
  bool get isSupplier =>
      kind == PartyKind.supplier || kind == PartyKind.both;
  bool get owesUs => balance.isPositive;

  /// How much more this customer may take on account before the till should
  /// object. A limit of zero means no limit — that is how shops use the field.
  Money get headroom => creditLimit.isZero
      ? Money(1 << 40)
      : Money(creditLimit.minor - balance.minor);

  bool wouldExceedLimit(Money extra) =>
      !creditLimit.isZero && balance.minor + extra.minor > creditLimit.minor;
}

/// One line of an account statement, with the balance as it stood after it.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.entryNo,
    required this.sourceType,
    required this.memo,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final String date;
  final String entryNo;
  final String sourceType;
  final String memo;
  final Money debit;
  final Money credit;
  final Money balance;
}

/// An invoice with something still outstanding on it.
class OpenDocument {
  const OpenDocument({
    required this.docType,
    required this.docId,
    required this.number,
    required this.issuedAt,
    required this.total,
    required this.due,
  });

  final String docType;
  final int docId;
  final String number;
  final String issuedAt;
  final Money total;
  final Money due;
}

/// How much of a payment goes against which invoice.
class PaymentAllocation {
  const PaymentAllocation({
    required this.docType,
    required this.docId,
    required this.amount,
  });

  final String docType;
  final int docId;
  final Money amount;
}

/// A receipt from a customer, or a payment to a supplier.
class SettlementRequest {
  const SettlementRequest({
    required this.partyId,
    required this.amount,
    required this.isReceipt,
    this.methodKey = 'cash',
    this.discount = Money.zero,
    this.userId,
    this.reference,
    this.note,
    this.at,
    this.allocations = const <PaymentAllocation>[],
  });

  final int partyId;
  final Money amount;

  /// True for money coming in from a customer, false for money going out to a
  /// supplier. The two post in mirror image, and nothing else differs.
  final bool isReceipt;

  final String methodKey;

  /// A discount allowed off the debt when it is settled — common when a
  /// customer clears an old balance in cash.
  final Money discount;

  final int? userId;
  final String? reference;
  final String? note;
  final DateTime? at;
  final List<PaymentAllocation> allocations;
}

/// Saving a customer or a supplier.
class PartySaveRequest {
  const PartySaveRequest({
    this.id,
    required this.name,
    required this.kind,
    this.phone,
    this.phone2,
    this.email,
    this.address,
    this.note,
    this.creditLimit = Money.zero,
    this.isActive = true,
  });

  final int? id;
  final String name;
  final PartyKind kind;
  final String? phone;
  final String? phone2;
  final String? email;
  final String? address;
  final String? note;
  final Money creditLimit;
  final bool isActive;
}
