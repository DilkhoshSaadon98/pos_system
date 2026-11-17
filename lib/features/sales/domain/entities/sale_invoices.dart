import 'package:cashier_system_v2/core/money/money.dart';

//? A saved invoice, read back for the list, the receipt and the return screen.
class SaleInvoice {
   final int id;
  final String invoiceNo;
  final String docType;
  final String issuedAt;
  final Money total;
  final Money paid;
  final Money due;
  final Money cost;
  final Money profit;
  final Money discount;
  final Money tax;
  final int itemsCount;
  final String status;
  final int? partyId;
  final String? partyName;
  final String? cashierName;
  final String? note;
  final int? returnOfId;
  final int? journalEntryId;
  const SaleInvoice({
    required this.id,
    required this.invoiceNo,
    required this.docType,
    required this.issuedAt,
    required this.total,
    required this.paid,
    required this.due,
    required this.cost,
    required this.profit,
    required this.discount,
    required this.tax,
    required this.itemsCount,
    required this.status,
    this.partyId,
    this.partyName,
    this.cashierName,
    this.note,
    this.returnOfId,
    this.journalEntryId,
  });

  factory SaleInvoice.fromMap(Map<String, Object?> m) => SaleInvoice(
        id: m['id'] as int,
        invoiceNo: '${m['invoice_no']}',
        docType: '${m['doc_type']}',
        issuedAt: '${m['issued_at']}',
        total: Money.fromDb(m['total_minor']),
        paid: Money.fromDb(m['paid_minor']),
        due: Money.fromDb(m['due_minor']),
        cost: Money.fromDb(m['cost_minor']),
        profit: Money.fromDb(m['profit_minor']),
        discount: Money.fromDb(m['discount_total_minor']),
        tax: Money.fromDb(m['tax_minor']),
        itemsCount: m['items_count'] as int? ?? 0,
        status: '${m['status']}',
        partyId: m['party_id'] as int?,
        partyName: m['party_name'] as String?,
        cashierName: m['cashier_name'] as String?,
        note: m['note'] as String?,
        returnOfId: m['return_of_id'] as int?,
        journalEntryId: m['journal_entry_id'] as int?,
      );

 

  bool get isReturn => docType == 'sale_return';
  bool get isVoid => status == 'void';
  bool get isPaid => due.isZero;
  bool get isFullyReturned => status == 'returned';
  bool get isPartlyReturned => status == 'partially_returned';

  /// A return is stored with positive figures and a document type that says
  /// which way round it goes; every report that adds invoices up has to know
  /// which sign to use, so it is answered here once.
  int get signedTotalMinor => isReturn ? -total.minor : total.minor;
}
