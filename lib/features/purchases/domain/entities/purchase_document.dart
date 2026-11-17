import '../../../../core/money/money.dart';

class PostedPurchase {
  const PostedPurchase({
    required this.invoiceId,
    required this.invoiceNo,
    required this.journalEntryId,
    required this.issuedAt,
    required this.totalMinor,
  });

  final int invoiceId;
  final String invoiceNo;
  final int journalEntryId;
  final String issuedAt;
  final int totalMinor;

  Money get total => Money(totalMinor);
}

/// A saved purchase, read back for the list and the return screen.
class PurchaseInvoice {
  const PurchaseInvoice({
    required this.id,
    required this.invoiceNo,
    required this.docType,
    required this.issuedAt,
    required this.total,
    required this.paid,
    required this.due,
    required this.fees,
    required this.discount,
    required this.tax,
    required this.itemsCount,
    required this.status,
    this.partyId,
    this.partyName,
    this.supplierRef,
    this.userName,
    this.note,
    this.journalEntryId,
    this.returnOfId,
  });

  factory PurchaseInvoice.fromMap(Map<String, Object?> m) => PurchaseInvoice(
        id: m['id'] as int,
        invoiceNo: '${m['invoice_no']}',
        docType: '${m['doc_type']}',
        issuedAt: '${m['issued_at']}',
        total: Money.fromDb(m['total_minor']),
        paid: Money.fromDb(m['paid_minor']),
        due: Money.fromDb(m['due_minor']),
        fees: Money.fromDb(m['fees_minor']),
        discount: Money.fromDb(m['discount_total_minor']),
        tax: Money.fromDb(m['tax_minor']),
        itemsCount: m['items_count'] as int? ?? 0,
        status: '${m['status']}',
        partyId: m['party_id'] as int?,
        partyName: m['party_name'] as String?,
        supplierRef: m['supplier_ref'] as String?,
        userName: m['user_name'] as String?,
        note: m['note'] as String?,
        journalEntryId: m['journal_entry_id'] as int?,
        returnOfId: m['return_of_id'] as int?,
      );

  final int id;
  final String invoiceNo;
  final String docType;
  final String issuedAt;
  final Money total;
  final Money paid;
  final Money due;
  final Money fees;
  final Money discount;
  final Money tax;
  final int itemsCount;
  final String status;
  final int? partyId;
  final String? partyName;
  final String? supplierRef;
  final String? userName;
  final String? note;
  final int? journalEntryId;
  final int? returnOfId;

  bool get isReturn => docType == 'purchase_return';
  bool get isVoid => status == 'void';
  bool get isPaid => due.isZero;
  bool get isFullyReturned => status == 'returned';
  bool get isPartlyReturned => status == 'partially_returned';

  int get signedTotalMinor => isReturn ? -total.minor : total.minor;
}

/// One line of a saved purchase.
class PurchaseInvoiceLine {
  const PurchaseInvoiceLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.factorMilli,
    required this.qtyMilli,
    required this.qtyBaseMilli,
    required this.unitCost,
    required this.landedUnitCost,
    required this.landedTotal,
    required this.discount,
    required this.fee,
    required this.net,
    required this.tax,
    required this.returnedQtyMilli,
    this.itemUnitId,
    this.newSellPrice,
  });

  factory PurchaseInvoiceLine.fromMap(Map<String, Object?> m) =>
      PurchaseInvoiceLine(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name'] ?? ''}',
        unitName: '${m['unit_name'] ?? ''}',
        factorMilli: m['factor_milli'] as int? ?? 1000,
        qtyMilli: m['qty_milli'] as int? ?? 0,
        qtyBaseMilli: m['qty_base_milli'] as int? ?? 0,
        unitCost: Money.fromDb(m['unit_cost_minor']),
        landedUnitCost: Money.fromDb(m['landed_unit_cost_minor']),
        landedTotal: Money.fromDb(m['landed_total_minor']),
        discount: Money.fromDb(
          (m['line_discount_minor'] as int? ?? 0) +
              (m['alloc_discount_minor'] as int? ?? 0),
        ),
        fee: Money.fromDb(m['alloc_fee_minor']),
        net: Money.fromDb(m['net_minor']),
        tax: Money.fromDb(m['tax_minor']),
        returnedQtyMilli: m['returned_qty_milli'] as int? ?? 0,
        itemUnitId: m['item_unit_id'] as int?,
        newSellPrice: m['new_sell_price_minor'] == null
            ? null
            : Money.fromDb(m['new_sell_price_minor']),
      );

  final int id;
  final int itemId;
  final String itemName;
  final String unitName;
  final int factorMilli;
  final int qtyMilli;
  final int qtyBaseMilli;
  final Money unitCost;

  /// What these goods really cost per base unit once the supplier's discount
  /// was taken off and the freight was added on.
  final Money landedUnitCost;

  final Money landedTotal;
  final Money discount;
  final Money fee;
  final Money net;
  final Money tax;
  final int returnedQtyMilli;
  final int? itemUnitId;
  final Money? newSellPrice;

  int get returnableQtyMilli =>
      qtyMilli - returnedQtyMilli < 0 ? 0 : qtyMilli - returnedQtyMilli;
}

class PurchaseInvoiceDetail {
  const PurchaseInvoiceDetail({required this.invoice, required this.lines});

  final PurchaseInvoice invoice;
  final List<PurchaseInvoiceLine> lines;
}

/// One line the shop is sending back to the supplier.
class PurchaseReturnLine {
  const PurchaseReturnLine({
    required this.originLineId,
    required this.itemId,
    required this.qtyMilli,
    required this.factorMilli,
    required this.landedUnitCostMinor,
    required this.unitCostMinor,
    required this.taxRateBp,
    this.itemUnitId,
    this.unitName = '',
  });

  final int originLineId;
  final int itemId;
  final int qtyMilli;
  final int factorMilli;

  /// The cost the goods came in at. Sending them back at anything else would
  /// leave the remaining stock carrying a cost that was never paid.
  final int landedUnitCostMinor;

  final int unitCostMinor;
  final int taxRateBp;
  final int? itemUnitId;
  final String unitName;

  int get qtyBaseMilli => (qtyMilli * factorMilli) ~/ 1000;
}

class PurchaseReturnRequest {
  const PurchaseReturnRequest({
    required this.originInvoiceId,
    required this.partyId,
    required this.lines,
    required this.refundToCash,
    this.userId,
    this.reason,
    this.refundAccountKey,
  });

  final int originInvoiceId;
  final int partyId;
  final List<PurchaseReturnLine> lines;

  /// Money back from the supplier, or a reduction of what the shop owes them.
  final bool refundToCash;

  final int? userId;
  final String? reason;
  final String? refundAccountKey;
}

class PurchasesQuery {
  const PurchasesQuery({
    required this.from,
    required this.to,
    this.partyId,
    this.search,
    this.docType,
    this.onlyUnpaid = false,
  });

  final DateTime from;
  final DateTime to;
  final int? partyId;
  final String? search;
  final String? docType;
  final bool onlyUnpaid;

  PurchasesQuery copyWith({
    DateTime? from,
    DateTime? to,
    int? partyId,
    bool clearParty = false,
    String? search,
    String? docType,
    bool clearDocType = false,
    bool? onlyUnpaid,
  }) =>
      PurchasesQuery(
        from: from ?? this.from,
        to: to ?? this.to,
        partyId: clearParty ? null : (partyId ?? this.partyId),
        search: search ?? this.search,
        docType: clearDocType ? null : (docType ?? this.docType),
        onlyUnpaid: onlyUnpaid ?? this.onlyUnpaid,
      );
}

class PurchasesSummary {
  const PurchasesSummary({
    required this.total,
    required this.paid,
    required this.due,
    required this.fees,
    required this.count,
    required this.returnsTotal,
  });

  static const PurchasesSummary empty = PurchasesSummary(
    total: Money.zero,
    paid: Money.zero,
    due: Money.zero,
    fees: Money.zero,
    count: 0,
    returnsTotal: Money.zero,
  );

  final Money total;
  final Money paid;
  final Money due;
  final Money fees;
  final int count;
  final Money returnsTotal;

  static PurchasesSummary of(List<PurchaseInvoice> invoices) {
    int total = 0;
    int paid = 0;
    int due = 0;
    int fees = 0;
    int returns = 0;

    for (final PurchaseInvoice i in invoices) {
      if (i.isVoid) continue;
      final int sign = i.isReturn ? -1 : 1;
      total += sign * i.total.minor;
      paid += sign * i.paid.minor;
      due += sign * i.due.minor;
      fees += sign * i.fees.minor;
      if (i.isReturn) returns += i.total.minor;
    }

    return PurchasesSummary(
      total: Money(total),
      paid: Money(paid),
      due: Money(due),
      fees: Money(fees),
      count: invoices.where((PurchaseInvoice i) => !i.isVoid).length,
      returnsTotal: Money(returns),
    );
  }
}
