import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/accounting/journal.dart';
import '../../../../core/calc/purchase_calculator.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/shifts/shift_service.dart';
import '../../../../core/utils/audit.dart';
import '../../../orders/orders_feature.dart';
import '../../../../core/inventory/batch_service.dart';
import '../../../../core/inventory/stock_service.dart';
import '../../../../core/money/arithmetic.dart';
import '../../../../core/utils/time.dart';
import '../../../parties/data/datasources/parties_local_datasource.dart';
import '../../domain/entities/purchase_document.dart';

/// Writing a purchase to the database.
///
/// The important part is what happens to cost: each line's **landed** cost —
/// its share of the supplier discount taken off and its share of the freight
/// added on — is what enters stock, converted to the base unit. Buy ten cartons
/// of twelve and the item gains a hundred and twenty pieces, each carrying one
/// hundred-and-twentieth of what those cartons really cost. The old code
/// multiplied a line total by the quantity a second time and never touched the
/// item's cost at all.
class PurchasesLocalDataSource {
  PurchasesLocalDataSource(this._database);

  final AppDatabase _database;

  // ------------------------------------------------------------ posting ----

  Future<PostedPurchase> postPurchase({
    required PurchaseTotals totals,
    required int partyId,
    int? userId,
    String paymentMethodKey = AccountKeys.cash,
    String? supplierRef,
    String? note,
    DateTime? issuedAt,
    bool updateSellPrices = true,

    /// The order this delivery fulfils, when it came from one. Applied inside
    /// the same transaction as the invoice: an order that says goods arrived
    /// while the invoice failed would be worse than one that says nothing.
    int? orderId,
  }) async {
    if (totals.lines.isEmpty) {
      throw const AppFailure.validation(
        'Add at least one item to the purchase.',
      );
    }

    return _database.transaction<PostedPurchase>((Transaction txn) async {
      // Tagged with the open drawer when there is one, but never required: a
      // delivery that arrives before the till is opened is a normal morning,
      // and refusing it would teach shops to post purchases with false dates.
      final int? shiftId = await ShiftService.openShiftId(txn, userId: userId);

      final String stamp = Time.stamp(issuedAt);
      final String invoiceNo = await AppDatabase.nextDocumentNumber(
        txn,
        'purchase_invoice',
        at: issuedAt,
      );

      final int invoiceId =
          await txn.insert('purchase_invoices', <String, Object?>{
        'invoice_no': invoiceNo,
        'doc_type': 'purchase',
        'party_id': partyId,
        'supplier_ref': supplierRef,
        'issued_at': stamp,
        'user_id': userId,
        'shift_id': shiftId,
        'gross_minor': totals.grossMinor,
        'line_discount_minor': totals.lineDiscountMinor,
        'invoice_discount_minor': totals.invoiceDiscountMinor,
        'discount_total_minor': totals.discountTotalMinor,
        'fees_minor': totals.feesMinor,
        'subtotal_minor': totals.subtotalMinor,
        'tax_minor': totals.taxMinor,
        'rounding_minor': totals.roundingMinor,
        'total_minor': totals.totalMinor,
        'paid_minor': totals.paidMinor,
        'due_minor': totals.dueMinor,
        'items_count': totals.itemsCount,
        'status': 'posted',
        'note': note,
        'created_at': stamp,
        'updated_at': stamp,
      });

      int lineNo = 0;
      for (final PurchaseLineTotals line in totals.lines) {
        final PurchaseLineInput input = line.input;
        final int lineId =
            await txn.insert('purchase_invoice_lines', <String, Object?>{
          'invoice_id': invoiceId,
          'item_id': input.itemId,
          'item_unit_id': input.itemUnitId,
          'unit_name': input.unitName,
          'factor_milli': input.factorMilli,
          'qty_milli': input.qtyMilli,
          'qty_base_milli': line.qtyBaseMilli,
          'unit_cost_minor': input.unitCostMinor,
          'gross_minor': line.grossMinor,
          'line_discount_minor': line.lineDiscountMinor,
          'alloc_discount_minor': line.allocDiscountMinor,
          'alloc_fee_minor': line.allocFeeMinor,
          'net_minor': line.netMinor,
          'landed_total_minor': line.landedTotalMinor,
          'landed_unit_cost_minor': line.landedUnitCostMinor,
          'tax_rate_bp': input.taxRateBp,
          'tax_minor': line.taxMinor,
          'new_sell_price_minor': input.newSellPriceMinor,
          'note': input.note,
          'line_no': lineNo++,
        });

        // A delivery of a batch-tracked item goes onto its own batch, so the
        // expiry report knows what is on the shelf and FEFO knows what to sell
        // first. The batch holds quantity and dates only — the value of the
        // stock is still the moving average this receipt just updated.
        int? batchId;
        if (input.hasBatch || await BatchService.tracksBatches(txn, input.itemId)) {
          BatchService.guardReceivedExpiry(input.expiryDate);
          batchId = await BatchService.upsert(
            txn,
            itemId: input.itemId,
            batchNo: input.batchNo,
            expiryDate: input.expiryDate,
            productionDate: input.productionDate,
            unitCostMinor: line.landedUnitCostMinor,
            partyId: partyId,
            docType: 'purchase',
            docId: invoiceId,
            receivedAt: stamp,
          );
        }

        await StockService.receive(
          txn,
          itemId: input.itemId,
          qtyBaseMilli: line.qtyBaseMilli,
          unitCostMinor: line.landedUnitCostMinor,
          kind: 'purchase',
          docType: 'purchase',
          docId: invoiceId,
          docLineId: lineId,
          userId: userId,
          movedAt: stamp,
          note: invoiceNo,
          batchId: batchId,
        );

        if (updateSellPrices &&
            input.newSellPriceMinor != null &&
            input.itemUnitId != null) {
          await txn.update(
            'item_units',
            <String, Object?>{'sell_price_minor': input.newSellPriceMinor},
            where: 'id = ?',
            whereArgs: <Object?>[input.itemUnitId],
          );
        }
      }

      final int entryId = await _postPurchaseJournal(
        txn,
        totals: totals,
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        partyId: partyId,
        userId: userId,
        paymentMethodKey: paymentMethodKey,
        date: stamp.substring(0, 10),
        shiftId: shiftId,
      );

      await txn.update(
        'purchase_invoices',
        <String, Object?>{'journal_entry_id': entryId},
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
      );

      if (orderId != null) {
        // Two lines of the same item on one delivery are one arrival as far as
        // the order is concerned, so the quantities are added up rather than
        // overwriting each other.
        final Map<int, int> arrived = <int, int>{};
        for (final PurchaseLineTotals l in totals.lines) {
          arrived.update(
            l.input.itemId,
            (int had) => had + l.input.qtyMilli,
            ifAbsent: () => l.input.qtyMilli,
          );
        }
        await OrdersLocalDataSource.applyReceipt(
          txn,
          orderId: orderId,
          invoiceId: invoiceId,
          receivedByItem: arrived,
        );
      }

      await Audit.write(
        txn,
        action: Audit.purchase,
        entity: 'purchase_invoice',
        entityId: invoiceId,
        userId: userId,
        shiftId: shiftId,
        detail: '$invoiceNo · ${totals.totalMinor}',
      );

      return PostedPurchase(
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        journalEntryId: entryId,
        issuedAt: stamp,
        totalMinor: totals.totalMinor,
      );
    });
  }

  /// ```
  /// Dr  Inventory        goods after discount, plus freight — the landed cost
  /// Dr  Tax payable      recoverable input tax
  /// Dr  Rounding         when the bill was rounded up
  ///     Cr  Cash / Bank  what was paid now
  ///     Cr  Accounts payable (supplier)  what is still owed
  ///     Cr  Rounding     when the bill was rounded down
  /// ```
  ///
  /// A credit purchase in the old app debited *inventory* and credited
  /// *suppliers* the wrong way round, so buying on account reduced both the
  /// stock value and the amount owed. This posting is the correct direction and
  /// it lands on the supplier's own sub-account, so the supplier statement
  /// finally shows purchases.
  Future<int> _postPurchaseJournal(
    DatabaseExecutor txn, {
    required PurchaseTotals totals,
    required int invoiceId,
    required String invoiceNo,
    required int partyId,
    required int? userId,
    required String paymentMethodKey,
    required String date,
    int? shiftId,
  }) async {
    final List<JournalLine> lines = <JournalLine>[
      JournalLine.debit(
        await AppDatabase.accountIdIn(txn, AccountKeys.inventory),
        totals.inventoryValueMinor,
        memo: invoiceNo,
      ),
    ];

    if (totals.taxMinor > 0) {
      lines.add(JournalLine.debit(
        await AppDatabase.accountIdIn(txn, AccountKeys.taxPayable),
        totals.taxMinor,
        memo: invoiceNo,
      ));
    }

    if (totals.roundingMinor != 0) {
      final int roundingId =
          await AppDatabase.accountIdIn(txn, AccountKeys.rounding);
      lines.add(totals.roundingMinor > 0
          ? JournalLine.debit(roundingId, totals.roundingMinor, memo: invoiceNo)
          : JournalLine.credit(roundingId, -totals.roundingMinor,
              memo: invoiceNo));
    }

    if (totals.paidMinor > 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, paymentMethodKey),
        totals.paidMinor,
        memo: invoiceNo,
      ));
    }
    if (totals.dueMinor > 0) {
      lines.add(JournalLine.credit(
        await PartiesLocalDataSource.ensureAccount(
            txn, partyId, AccountKeys.payable),
        totals.dueMinor,
        partyId: partyId,
        memo: invoiceNo,
      ));
    }

    return Journal.post(
      txn,
      sourceType: 'purchase',
      sourceId: invoiceId,
      entryDate: date,
      memo: 'Purchase $invoiceNo',
      userId: userId,
      shiftId: shiftId,
      lines: lines,
    );
  }

  // ------------------------------------------------------------ returns ----

  /// Sending goods back.
  ///
  /// ```
  /// Dr  Accounts payable / Cash   what the supplier gives back
  ///     Cr  Inventory             the goods, at the cost they came in at
  ///     Cr  Tax payable           the input tax that was claimed on them
  /// ```
  ///
  /// The cost used is the **landed** unit cost recorded on the original line,
  /// not today's average: the shop is handing back exactly what it received,
  /// and valuing it at anything else would leave the remaining stock carrying a
  /// cost nobody ever paid.
  Future<PostedPurchase> postReturn(PurchaseReturnRequest request) async {
    if (request.lines.isEmpty) {
      throw const AppFailure.validation('Choose what is going back.');
    }

    return _database.transaction<PostedPurchase>((Transaction txn) async {
      final String stamp = Time.stamp();
      final String invoiceNo =
          await AppDatabase.nextDocumentNumber(txn, 'purchase_return');

      final List<Map<String, Object?>> originRows = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: <Object?>[request.originInvoiceId],
        limit: 1,
      );
      if (originRows.isEmpty) {
        throw const AppFailure.notFound('That purchase no longer exists.');
      }
      if ('${originRows.first['status']}' == 'void') {
        throw const AppFailure.conflict(
          'That purchase was cancelled — there is nothing to send back.',
        );
      }

      final int? shiftId =
          await ShiftService.openShiftId(txn, userId: request.userId);

      final int returnId =
          await txn.insert('purchase_invoices', <String, Object?>{
        'invoice_no': invoiceNo,
        'doc_type': 'purchase_return',
        'party_id': request.partyId,
        'issued_at': stamp,
        'user_id': request.userId,
        'shift_id': shiftId,
        'status': 'posted',
        'return_of_id': request.originInvoiceId,
        'note': request.reason,
        'items_count': request.lines.length,
        'created_at': stamp,
        'updated_at': stamp,
      });

      int goodsValue = 0;
      int taxTotal = 0;
      int lineNo = 0;

      for (final PurchaseReturnLine line in request.lines) {
        if (line.qtyMilli <= 0) continue;

        final int landed =
            mulDivRound(line.landedUnitCostMinor, line.qtyBaseMilli, 1000);
        final int gross =
            mulDivRound(line.unitCostMinor, line.qtyMilli, 1000);
        final int tax = line.taxRateBp <= 0
            ? 0
            : mulDivRound(landed, line.taxRateBp, 10000);

        final int lineId =
            await txn.insert('purchase_invoice_lines', <String, Object?>{
          'invoice_id': returnId,
          'item_id': line.itemId,
          'item_unit_id': line.itemUnitId,
          'unit_name': line.unitName,
          'factor_milli': line.factorMilli,
          'qty_milli': line.qtyMilli,
          'qty_base_milli': line.qtyBaseMilli,
          'unit_cost_minor': line.unitCostMinor,
          'gross_minor': gross,
          'net_minor': landed,
          'landed_total_minor': landed,
          'landed_unit_cost_minor': line.landedUnitCostMinor,
          'tax_rate_bp': line.taxRateBp,
          'tax_minor': tax,
          'origin_line_id': line.originLineId,
          'line_no': lineNo++,
        });

        // Out of stock at the cost it came in at. The average is deliberately
        // left alone: an issue never moves it, which is the definition of a
        // moving average and what keeps two sales at the same moment costing
        // the same.
        await StockService.issue(
          txn,
          itemId: line.itemId,
          qtyBaseMilli: line.qtyBaseMilli,
          kind: 'purchase_return',
          unitCostOverrideMinor: line.landedUnitCostMinor,
          docType: 'purchase_return',
          docId: returnId,
          docLineId: lineId,
          userId: request.userId,
          movedAt: stamp,
          note: invoiceNo,
          allowNegativeOverride: true,
        );

        await txn.rawUpdate(
          'UPDATE purchase_invoice_lines '
          '   SET returned_qty_milli = IFNULL(returned_qty_milli, 0) + ? '
          ' WHERE id = ?',
          <Object?>[line.qtyMilli, line.originLineId],
        );

        goodsValue += landed;
        taxTotal += tax;
      }

      final int total = goodsValue + taxTotal;

      await txn.update(
        'purchase_invoices',
        <String, Object?>{
          'gross_minor': goodsValue,
          'subtotal_minor': goodsValue,
          'tax_minor': taxTotal,
          'total_minor': total,
          'paid_minor': request.refundToCash ? total : 0,
          'due_minor': request.refundToCash ? 0 : total,
          'updated_at': stamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[returnId],
      );

      final List<JournalLine> journal = <JournalLine>[];
      if (total > 0) {
        journal.add(request.refundToCash
            ? JournalLine.debit(
                await AppDatabase.accountIdIn(
                  txn,
                  request.refundAccountKey ?? AccountKeys.cash,
                ),
                total,
                memo: invoiceNo,
              )
            : JournalLine.debit(
                await PartiesLocalDataSource.ensureAccount(
                    txn, request.partyId, AccountKeys.payable),
                total,
                partyId: request.partyId,
                memo: invoiceNo,
              ));
      }
      if (goodsValue > 0) {
        journal.add(JournalLine.credit(
          await AppDatabase.accountIdIn(txn, AccountKeys.inventory),
          goodsValue,
          memo: invoiceNo,
        ));
      }
      if (taxTotal > 0) {
        journal.add(JournalLine.credit(
          await AppDatabase.accountIdIn(txn, AccountKeys.taxPayable),
          taxTotal,
          memo: invoiceNo,
        ));
      }

      final int entryId = await Journal.post(
        txn,
        sourceType: 'purchase_return',
        sourceId: returnId,
        entryDate: stamp.substring(0, 10),
        memo: 'Purchase return $invoiceNo',
        userId: request.userId,
        shiftId: shiftId,
        lines: journal,
      );

      await txn.update(
        'purchase_invoices',
        <String, Object?>{'journal_entry_id': entryId},
        where: 'id = ?',
        whereArgs: <Object?>[returnId],
      );

      await _refreshReturnStatus(txn, request.originInvoiceId, stamp);

      return PostedPurchase(
        invoiceId: returnId,
        invoiceNo: invoiceNo,
        journalEntryId: entryId,
        issuedAt: stamp,
        totalMinor: total,
      );
    });
  }

  Future<void> _refreshReturnStatus(
    DatabaseExecutor txn,
    int invoiceId,
    String stamp,
  ) async {
    final List<Map<String, Object?>> rows = await txn.rawQuery(
      '''
      SELECT SUM(qty_milli)                     AS bought,
             SUM(IFNULL(returned_qty_milli, 0)) AS returned
        FROM purchase_invoice_lines
       WHERE invoice_id = ?
      ''',
      <Object?>[invoiceId],
    );
    final int bought = (rows.first['bought'] as num?)?.toInt() ?? 0;
    final int returned = (rows.first['returned'] as num?)?.toInt() ?? 0;

    await txn.update(
      'purchase_invoices',
      <String, Object?>{
        'status': returned <= 0
            ? 'posted'
            : returned >= bought
                ? 'returned'
                : 'partially_returned',
        'updated_at': stamp,
      },
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
    );
  }

  // ------------------------------------------------------------ voiding ----

  Future<void> voidPurchase({required int invoiceId, int? userId}) async {
    await _database.transaction<void>((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const AppFailure.notFound('That purchase no longer exists.');
      }
      final Map<String, Object?> invoice = rows.first;
      if ('${invoice['status']}' == 'void') {
        throw const AppFailure.conflict('That purchase is already cancelled.');
      }

      final List<Map<String, Object?>> allocated = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM payment_allocations '
        " WHERE doc_type = 'purchase' AND doc_id = ?",
        <Object?>[invoiceId],
      );
      if ((allocated.first['n'] as int? ?? 0) > 0) {
        throw const AppFailure.conflict(
          'A payment has been applied to this purchase. Cancel the payment '
          'first.',
        );
      }
      final List<Map<String, Object?>> returned = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM purchase_invoices WHERE return_of_id = ?',
        <Object?>[invoiceId],
      );
      if ((returned.first['n'] as int? ?? 0) > 0) {
        throw const AppFailure.conflict(
          'Part of this purchase has already been sent back.',
        );
      }

      final String stamp = Time.stamp();
      final bool isReturn = '${invoice['doc_type']}' == 'purchase_return';

      final List<Map<String, Object?>> lines = await txn.query(
        'purchase_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: <Object?>[invoiceId],
      );

      for (final Map<String, Object?> line in lines) {
        final int qty = line['qty_base_milli'] as int? ?? 0;
        if (qty <= 0) continue;
        final int landed = line['landed_unit_cost_minor'] as int? ?? 0;

        if (isReturn) {
          await StockService.receive(
            txn,
            itemId: line['item_id'] as int,
            qtyBaseMilli: qty,
            unitCostMinor: landed,
            kind: 'adjustment',
            docType: 'void',
            docId: invoiceId,
            userId: userId,
            movedAt: stamp,
            note: '${invoice['invoice_no']}',
            updateAverage: false,
          );
        } else {
          await StockService.issue(
            txn,
            itemId: line['item_id'] as int,
            qtyBaseMilli: qty,
            kind: 'adjustment',
            unitCostOverrideMinor: landed,
            docType: 'void',
            docId: invoiceId,
            userId: userId,
            movedAt: stamp,
            note: '${invoice['invoice_no']}',
            allowNegativeOverride: true,
          );
        }
      }

      final int? entryId = invoice['journal_entry_id'] as int?;
      if (entryId != null) {
        await Journal.reverse(
          txn,
          entryId,
          memo: 'Void ${invoice['invoice_no']}',
          userId: userId,
          shiftId: await ShiftService.openShiftId(txn, userId: userId),
        );
      }

      await txn.update(
        'purchase_invoices',
        <String, Object?>{'status': 'void', 'updated_at': stamp},
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
      );

      final int? originId = invoice['return_of_id'] as int?;
      if (originId != null) {
        for (final Map<String, Object?> line in lines) {
          final int? origin = line['origin_line_id'] as int?;
          if (origin == null) continue;
          await txn.rawUpdate(
            'UPDATE purchase_invoice_lines '
            '   SET returned_qty_milli = MAX(IFNULL(returned_qty_milli,0) - ?, 0) '
            ' WHERE id = ?',
            <Object?>[line['qty_milli'], origin],
          );
        }
        await _refreshReturnStatus(txn, originId, stamp);
      }
    });
  }

  // ------------------------------------------------------------- reading ---

  Future<List<PurchaseInvoice>> search(PurchasesQuery query) async {
    final StringBuffer where = StringBuffer('issued_at BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[
      Time.startOfDay(query.from),
      Time.endOfDay(query.to),
    ];

    if (query.partyId != null) {
      where.write(' AND party_id = ?');
      args.add(query.partyId);
    }
    if (query.docType != null) {
      where.write(' AND doc_type = ?');
      args.add(query.docType);
    }
    if (query.onlyUnpaid) {
      where.write(" AND due_minor > 0 AND status <> 'void'");
    }
    final String q = (query.search ?? '').trim();
    if (q.isNotEmpty) {
      where.write(
          ' AND (invoice_no LIKE ? OR party_name LIKE ? OR supplier_ref LIKE ?)');
      args
        ..add('%$q%')
        ..add('%$q%')
        ..add('%$q%');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_purchase_invoices_full',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'issued_at DESC, id DESC',
    );
    return rows.map(PurchaseInvoice.fromMap).toList();
  }

  Future<PurchaseInvoiceDetail> detail(int invoiceId) async {
    final List<Map<String, Object?>> head = await _database.db.query(
      'v_purchase_invoices_full',
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
      limit: 1,
    );
    if (head.isEmpty) {
      throw const AppFailure.notFound('That purchase no longer exists.');
    }
    return PurchaseInvoiceDetail(
      invoice: PurchaseInvoice.fromMap(head.first),
      lines: await _linesOf(invoiceId),
    );
  }

  Future<List<PurchaseInvoiceLine>> returnableLines(int invoiceId) async {
    final List<PurchaseInvoiceLine> lines = await _linesOf(invoiceId);
    return lines
        .where((PurchaseInvoiceLine l) => l.returnableQtyMilli > 0)
        .toList(growable: false);
  }

  Future<List<PurchaseInvoiceLine>> _linesOf(int invoiceId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT l.*,
             CASE WHEN i.variant_name IS NULL OR i.variant_name = ''
                  THEN i.name
                  ELSE i.name || ' — ' || i.variant_name END AS item_name
        FROM purchase_invoice_lines l
        JOIN items i ON i.id = l.item_id
       WHERE l.invoice_id = ?
       ORDER BY l.line_no
      ''',
      <Object?>[invoiceId],
    );
    return rows.map(PurchaseInvoiceLine.fromMap).toList();
  }
}
