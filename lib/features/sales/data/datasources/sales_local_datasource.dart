import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_detail.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_query.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_request.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_tender.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/accounting/journal.dart';
import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/inventory/batch_service.dart';
import '../../../../core/inventory/bundle_service.dart';
import '../../../../core/inventory/stock_service.dart';
import '../../../../core/loyalty/loyalty_service.dart';
import '../../../../core/money/arithmetic.dart';
import '../../../../core/shifts/shift_service.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';


class SalesLocalDataSource {
  SalesLocalDataSource(this._database);

  final AppDatabase _database;

  bool get _pricesIncludeTax => _database.settingBool('prices_include_tax');
  bool get _shiftsRequired => _database.settingBool('shifts_required', true);

  //? -- posting ----

  Future<PostedSale> postSale({
    required SaleTotals totals,
    required List<TenderInput> tenders,
    int? partyId,
    int? userId,
    PriceMode priceMode = PriceMode.retail,
    String? note,
    DateTime? issuedAt,
    int pointsSpent = 0,
  }) async {
    if (totals.lines.isEmpty) {
      throw const AppFailure.validation('The cart is empty.');
    }
    if (totals.dueMinor > 0 && partyId == null) {
      throw const AppFailure.validation(
        'Choose a customer before leaving part of the bill unpaid.',
      );
    }

    return _database.transaction<PostedSale>((Transaction txn) async {
      final int? shiftId = await ShiftService.resolveForPosting(
        txn,
        enforce: _shiftsRequired,
        userId: userId,
      );

      final String stamp = Time.stamp(issuedAt);
      final String invoiceNo = await AppDatabase.nextDocumentNumber(
        txn,
        'sales_invoice',
        at: issuedAt,
      );

      final int invoiceId = await txn.insert('sales_invoices', <String, Object?>{
        'invoice_no': invoiceNo,
        'doc_type': 'sale',
        'party_id': partyId,
        'issued_at': stamp,
        'user_id': userId,
        'shift_id': shiftId,
        'price_mode': priceMode.dbValue,
        'gross_minor': totals.grossMinor,
        'line_discount_minor': totals.lineDiscountMinor,
        'invoice_discount_minor': totals.invoiceDiscountMinor,
        'discount_total_minor': totals.discountTotalMinor,
        'subtotal_minor': totals.subtotalMinor,
        'tax_minor': totals.taxMinor,
        'service_charge_minor': totals.serviceChargeMinor,
        'rounding_minor': totals.roundingMinor,
        'total_minor': totals.totalMinor,
        'paid_minor': totals.paidMinor,
        'change_minor': totals.changeMinor,
        'due_minor': totals.dueMinor,
        'cost_minor': 0,
        'profit_minor': 0,
        'items_count': totals.itemsCount,
        'status': 'posted',
        'note': note,
        'created_at': stamp,
        'updated_at': stamp,
      });

      final Map<int, ItemKind> kinds = await _kindsOf(
        txn,
        totals.lines.map((SaleLineTotals l) => l.input.itemId).toList(),
      );

      int actualCost = 0;
      int giftCost = 0;
      int goodsRevenue = 0;
      int serviceRevenue = 0;
      int lineNo = 0;

      for (final SaleLineTotals line in totals.lines) {
        final SaleLineInput input = line.input;
        final ItemKind kind = kinds[input.itemId] ?? ItemKind.stock;

        final int lineId =
            await txn.insert('sales_invoice_lines', <String, Object?>{
          'invoice_id': invoiceId,
          'item_id': input.itemId,
          'item_unit_id': input.itemUnitId,
          'unit_name': input.unitName,
          'factor_milli': input.factorMilli,
          'qty_milli': input.qtyMilli,
          'qty_base_milli': input.qtyBaseMilli,
          'unit_price_minor': input.unitPriceMinor,
          'gross_minor': line.grossMinor,
          'line_discount_minor': line.lineDiscountMinor,
          'alloc_discount_minor': line.allocDiscountMinor,
          'net_minor': line.netMinor,
          'tax_rate_bp': input.taxRateBp,
          'tax_minor': line.taxMinor,
          'total_minor': line.totalMinor,
          'unit_cost_minor': input.unitCostMinor,
          'cost_minor': line.costMinor,
          'is_gift': input.isGift ? 1 : 0,
          'promotion_id': input.promotionId,
          'note': input.note,
          'line_no': lineNo++,
        });

        final int cost = await _issueForLine(
          txn,
          kind: kind,
          itemId: input.itemId,
          qtyBaseMilli: input.qtyBaseMilli,
          unitCostMinor: input.unitCostMinor,
          invoiceId: invoiceId,
          lineId: lineId,
          userId: userId,
          stamp: stamp,
          note: invoiceNo,
        );

        // The stock ledger is the authority on what the goods cost. Write its
        // answer back onto the line so the invoice, the ledger and the profit
        // report can never tell three different stories.
        if (cost != line.costMinor) {
          await txn.update(
            'sales_invoice_lines',
            <String, Object?>{
              'cost_minor': cost,
              'unit_cost_minor': input.qtyBaseMilli == 0
                  ? 0
                  : mulDivRound(cost, 1000, input.qtyBaseMilli),
            },
            where: 'id = ?',
            whereArgs: <Object?>[lineId],
          );
        }

        actualCost += cost;
        if (input.isGift) giftCost += cost;

        // Revenue is split by what was sold: goods to sales, work to service
        // revenue. An income statement that lumps a delivery charge in with
        // merchandise cannot show a real gross margin.
        final int lineRevenue = line.taxableMinor + line.discountTaxableMinor;
        if (kind == ItemKind.service) {
          serviceRevenue += lineRevenue;
        } else {
          goodsRevenue += lineRevenue;
        }
      }

      for (final TenderInput t in tenders) {
        if (t.method == TenderMethod.credit || t.amountMinor == 0) continue;
        await txn.insert('sale_tenders', <String, Object?>{
          'invoice_id': invoiceId,
          'method': t.method.name,
          'account_id': t.accountId ??
              await AppDatabase.accountIdIn(txn, _tenderAccountKey(t)),
          'amount_minor': t.amountMinor,
          'reference': t.reference,
          'direction': 'in',
          // What actually changed hands, when it was not dinars.
          'currency_code': t.currencyCode,
          'fx_rate_milli': t.isForeign ? t.fxRateMilli : 0,
          'amount_fx_minor': t.isForeign ? t.amountFxMinor : 0,
        });
      }

      final int entryId = await _postSaleJournal(
        txn,
        totals: totals,
        tenders: tenders,
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        partyId: partyId,
        userId: userId,
        costMinor: actualCost,
        giftCostMinor: giftCost,
        goodsRevenueMinor: goodsRevenue,
        serviceRevenueMinor: serviceRevenue,
        date: stamp.substring(0, 10),
        shiftId: shiftId,
      );

      await txn.update(
        'sales_invoices',
        <String, Object?>{
          'journal_entry_id': entryId,
          'cost_minor': actualCost,
          'profit_minor': totals.subtotalMinor - actualCost,
        },
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
      );

      // Points: spent first — a customer cannot pay with points they are
      // about to earn on the same bill — then earned on what was actually paid.
      final LoyaltyRules loyalty = LoyaltyRules.fromSettings(_database);
      int spent = 0;
      int earned = 0;
      if (partyId != null && loyalty.enabled) {
        if (pointsSpent > 0) {
          spent = await LoyaltyService.redeem(
            txn,
            partyId: partyId,
            points: pointsSpent,
            rules: loyalty,
            docId: invoiceId,
            userId: userId,
          );
        }
        earned = await LoyaltyService.earn(
          txn,
          partyId: partyId,
          spentMinor: totals.totalMinor,
          rules: loyalty,
          docId: invoiceId,
          userId: userId,
        );
      }
      if (spent > 0 || earned > 0) {
        await txn.update(
          'sales_invoices',
          <String, Object?>{'points_spent': spent, 'points_earned': earned},
          where: 'id = ?',
          whereArgs: <Object?>[invoiceId],
        );
      }

      await Audit.write(
        txn,
        action: Audit.sale,
        entity: 'sales_invoice',
        entityId: invoiceId,
        userId: userId,
        shiftId: shiftId,
        detail: '$invoiceNo · ${totals.totalMinor}',
      );

      return PostedSale(
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        journalEntryId: entryId,
        issuedAt: stamp,
        totalMinor: totals.totalMinor,
        changeMinor: totals.changeMinor,
      );
    });
  }

  /// Takes the goods off the shelf and returns what they cost.
  ///
  /// A bundle is one line on the invoice and several movements in the ledger —
  /// the customer bought a meal, the shelf lost two burgers and a drink, each
  /// at its own average. A service moves nothing and costs nothing.
  Future<int> _issueForLine(
    DatabaseExecutor txn, {
    required ItemKind kind,
    required int itemId,
    required int qtyBaseMilli,
    required int unitCostMinor,
    required int invoiceId,
    required int lineId,
    required int? userId,
    required String stamp,
    required String note,
  }) async {
    if (kind == ItemKind.service) return 0;

    if (kind == ItemKind.bundle) {
      return BundleService.issueFor(
        txn,
        bundleItemId: itemId,
        qtyBundlesMilli: qtyBaseMilli,
        kind: 'sale',
        docType: 'sale',
        docId: invoiceId,
        docLineId: lineId,
        userId: userId,
        movedAt: stamp,
        note: note,
      );
    }

    // An item counted by batch leaves in first-expiry-first-out order, which
    // can mean two or three movements for one line: the last of a short-dated
    // box, then the next one. Each movement is valued at the same moving
    // average, so the cost of the line is unchanged by how it was split.
    if (await BatchService.tracksBatches(txn, itemId)) {
      final List<BatchPick> picks = await BatchService.pickFefo(
        txn,
        itemId: itemId,
        qtyBaseMilli: qtyBaseMilli,
      );

      if (picks.isNotEmpty) {
        int total = 0;
        for (final BatchPick pick in picks) {
          final StockIssue part = await StockService.issue(
            txn,
            itemId: itemId,
            qtyBaseMilli: pick.qtyMilli,
            kind: 'sale',
            unitCostOverrideMinor: unitCostMinor > 0 ? unitCostMinor : null,
            docType: 'sale',
            docId: invoiceId,
            docLineId: lineId,
            userId: userId,
            movedAt: stamp,
            note: pick.batchNo.isEmpty ? note : '$note · ${pick.batchNo}',
            batchId: pick.batchId,
          );
          total += part.costMinor;
        }
        return total;
      }
      // Nothing on the shelf in any batch — fall through and let the ordinary
      // path decide whether selling into negative stock is allowed at all.
    }

    final StockIssue issue = await StockService.issue(
      txn,
      itemId: itemId,
      qtyBaseMilli: qtyBaseMilli,
      kind: 'sale',
      unitCostOverrideMinor: unitCostMinor > 0 ? unitCostMinor : null,
      docType: 'sale',
      docId: invoiceId,
      docLineId: lineId,
      userId: userId,
      movedAt: stamp,
      note: note,
    );
    return issue.costMinor;
  }

  /// The bookkeeping of a sale, in full:
  ///
  /// ```
  /// Dr  Cash / Card / Bank      what the tills actually took, change deducted
  /// Dr  Accounts receivable     whatever the customer still owes
  /// Dr  Sales discounts         every discount given, tax excluded
  ///     Cr  Sales revenue       the goods at their undiscounted price
  ///     Cr  Service revenue     the work, and any service charge
  ///     Cr  Tax payable         tax collected on behalf of the state
  ///     Cr/Dr Rounding          the few units gained or lost rounding the bill
  ///
  /// Dr  Cost of goods sold      what the goods cost us
  /// Dr  Gifts and samples       the cost of anything given away
  ///     Cr  Inventory           stock leaves at the same value
  /// ```
  ///
  /// The old app posted a sale twice — once as a "sale" and once as a "receipt"
  /// between the same two accounts — which doubled the revenue on every cash
  /// sale, and it booked credit sales against a *customer row id* rather than
  /// the customer's account. Both are gone.
  Future<int> _postSaleJournal(
    DatabaseExecutor txn, {
    required SaleTotals totals,
    required List<TenderInput> tenders,
    required int invoiceId,
    required String invoiceNo,
    required int? partyId,
    required int? userId,
    required int costMinor,
    required int giftCostMinor,
    required int goodsRevenueMinor,
    required int serviceRevenueMinor,
    required String date,
    int? shiftId,
  }) async {
    final List<JournalLine> lines = <JournalLine>[];

    // --- money in -----------------------------------------------------------
    // Change comes out of the shop's own drawer, never out of the foreign one:
    // a customer who pays with a ten-dollar note is handed dinars back. So a
    // foreign tender is booked at its full converted value and the change is
    // credited to the dinar drawer below.
    int change = totals.changeMinor;
    for (final TenderInput t in tenders) {
      if (t.method == TenderMethod.credit || t.amountMinor == 0) continue;
      int amount = t.amountMinor;
      if (t.method == TenderMethod.cash && !t.isForeign && change > 0) {
        // The drawer keeps the tender minus the change handed back.
        final int used = change > amount ? amount : change;
        amount -= used;
        change -= used;
      }
      if (amount == 0) continue;
      final int accountId =
          t.accountId ?? await AppDatabase.accountIdIn(txn, _tenderAccountKey(t));
      lines.add(JournalLine.debit(accountId, amount, memo: invoiceNo));
    }

    // Change still owed after the local notes were counted: it was paid for
    // with foreign money, and it leaves the dinar drawer.
    if (change > 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, AccountKeys.cash),
        change,
        memo: 'Change $invoiceNo',
      ));
    }

    if (totals.dueMinor > 0) {
      lines.add(JournalLine.debit(
        await partyAccount(txn, partyId!, AccountKeys.receivable),
        totals.dueMinor,
        partyId: partyId,
        memo: invoiceNo,
      ));
    }
    if (totals.creditMinor > 0 && partyId != null) {
      // Paid more than the bill by card or bank: the customer is in credit.
      lines.add(JournalLine.credit(
        await partyAccount(txn, partyId, AccountKeys.receivable),
        totals.creditMinor,
        partyId: partyId,
        memo: 'Overpayment $invoiceNo',
      ));
    }

    // --- revenue ------------------------------------------------------------
    if (totals.discountTaxableMinor > 0) {
      lines.add(JournalLine.debit(
        await AppDatabase.accountIdIn(txn, AccountKeys.salesDiscounts),
        totals.discountTaxableMinor,
        memo: invoiceNo,
      ));
    }
    if (goodsRevenueMinor != 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, AccountKeys.sales),
        goodsRevenueMinor,
        memo: invoiceNo,
      ));
    }
    final int serviceTotal = serviceRevenueMinor + totals.serviceChargeMinor;
    if (serviceTotal != 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, AccountKeys.serviceRevenue),
        serviceTotal,
        memo: invoiceNo,
      ));
    }
    if (totals.taxMinor > 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, AccountKeys.taxPayable),
        totals.taxMinor,
        memo: invoiceNo,
      ));
    }
    if (totals.roundingMinor != 0) {
      final int roundingId =
          await AppDatabase.accountIdIn(txn, AccountKeys.rounding);
      lines.add(totals.roundingMinor > 0
          ? JournalLine.credit(roundingId, totals.roundingMinor, memo: invoiceNo)
          : JournalLine.debit(roundingId, -totals.roundingMinor,
              memo: invoiceNo));
    }

    // --- cost of what was sold ---------------------------------------------
    final int soldCost = costMinor - giftCostMinor;
    if (soldCost > 0) {
      lines.add(JournalLine.debit(
        await AppDatabase.accountIdIn(txn, AccountKeys.cogs),
        soldCost,
        memo: invoiceNo,
      ));
    }
    if (giftCostMinor > 0) {
      lines.add(JournalLine.debit(
        await AppDatabase.accountIdIn(txn, AccountKeys.gifts),
        giftCostMinor,
        memo: invoiceNo,
      ));
    }
    if (costMinor > 0) {
      lines.add(JournalLine.credit(
        await AppDatabase.accountIdIn(txn, AccountKeys.inventory),
        costMinor,
        memo: invoiceNo,
      ));
    }

    return Journal.post(
      txn,
      sourceType: 'sale',
      sourceId: invoiceId,
      entryDate: date,
      memo: 'Sale $invoiceNo',
      userId: userId,
      shiftId: shiftId,
      lines: lines,
    );
  }

  // ------------------------------------------------------------ returns ----

  /// Taking goods back.
  ///
  /// ```
  /// Dr  Sales returns           the revenue being given back
  /// Dr  Tax payable             the tax that was collected on it
  ///     Cr  Sales discounts     the discount that was allowed on it
  ///     Cr  Cash / Receivable   what the customer gets back
  ///
  /// Dr  Inventory               the goods, at the cost they left at
  ///     Cr  Cost of goods sold
  /// ```
  ///
  /// Goods that are not fit to sell again never touch inventory: their cost
  /// moves from cost of sales to shrinkage instead, which is the truth — the
  /// shop has neither the money nor the goods.
  Future<PostedSale> postReturn(SaleReturnRequest request) async {
    if (request.lines.isEmpty) {
      throw const AppFailure.validation('Choose what is being returned.');
    }
    if (!request.refundToCash && request.partyId == null) {
      throw const AppFailure.validation(
        'A refund to account needs a customer. Refund in cash instead.',
      );
    }

    return _database.transaction<PostedSale>((Transaction txn) async {
      // A refund leaves *today's* drawer, whichever shift took the money.
      final int? shiftId = await ShiftService.resolveForPosting(
        txn,
        enforce: _shiftsRequired && request.refundToCash,
        userId: request.userId,
      );

      final String stamp = Time.stamp();
      final String invoiceNo =
          await AppDatabase.nextDocumentNumber(txn, 'sales_return');

      final List<Map<String, Object?>> originRows = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: <Object?>[request.originInvoiceId],
        limit: 1,
      );
      if (originRows.isEmpty) {
        throw const AppFailure.notFound('That invoice no longer exists.');
      }
      if ('${originRows.first['status']}' == 'void') {
        throw const AppFailure.conflict(
          'That invoice was cancelled — there is nothing to return.',
        );
      }

      final Map<int, ItemKind> kinds = await _kindsOf(
        txn,
        request.lines.map((SaleReturnLine l) => l.itemId).toList(),
      );

      // ---- what the return is worth, line by line --------------------------
      int gross = 0;
      int discount = 0;
      int subtotal = 0;
      int taxTotal = 0;
      int discountTaxable = 0;
      int cost = 0;
      int goodsRevenue = 0;
      int serviceRevenue = 0;

      final int returnId = await txn.insert(
        'sales_invoices',
        <String, Object?>{
          'invoice_no': invoiceNo,
          'doc_type': 'sale_return',
          'party_id': request.partyId,
          'issued_at': stamp,
          'user_id': request.userId,
          'shift_id': shiftId,
          'price_mode': '${originRows.first['price_mode']}',
          'status': 'posted',
          'return_of_id': request.originInvoiceId,
          'note': request.reason,
          'items_count': request.lines.length,
          'created_at': stamp,
          'updated_at': stamp,
        },
      );

      int lineNo = 0;
      for (final SaleReturnLine line in request.lines) {
        if (line.qtyMilli <= 0) continue;

        final int lineGross =
            mulDivRound(line.unitPriceMinor, line.qtyMilli, 1000);
        final int lineDiscount =
            line.discountMinor > lineGross ? lineGross : line.discountMinor;
        final int net = lineGross - lineDiscount;

        late final int taxable;
        late final int tax;
        if (line.taxRateBp <= 0) {
          taxable = net;
          tax = 0;
        } else if (_pricesIncludeTax) {
          taxable = mulDivRound(net, 10000, 10000 + line.taxRateBp);
          tax = net - taxable;
        } else {
          taxable = net;
          tax = mulDivRound(net, line.taxRateBp, 10000);
        }
        final int lineDiscountTaxable =
            (line.taxRateBp > 0 && _pricesIncludeTax)
                ? mulDivRound(lineDiscount, 10000, 10000 + line.taxRateBp)
                : lineDiscount;

        final ItemKind kind = kinds[line.itemId] ?? ItemKind.stock;
        final int lineCost = kind == ItemKind.service
            ? 0
            : mulDivRound(line.unitCostMinor, line.qtyBaseMilli, 1000);

        final int lineId =
            await txn.insert('sales_invoice_lines', <String, Object?>{
          'invoice_id': returnId,
          'item_id': line.itemId,
          'item_unit_id': line.itemUnitId,
          'unit_name': line.unitName,
          'factor_milli': line.factorMilli,
          'qty_milli': line.qtyMilli,
          'qty_base_milli': line.qtyBaseMilli,
          'unit_price_minor': line.unitPriceMinor,
          'gross_minor': lineGross,
          'line_discount_minor': lineDiscount,
          'alloc_discount_minor': 0,
          'net_minor': net,
          'tax_rate_bp': line.taxRateBp,
          'tax_minor': tax,
          'total_minor': taxable + tax,
          'unit_cost_minor': line.unitCostMinor,
          'cost_minor': lineCost,
          'is_gift': 0,
          'origin_line_id': line.originLineId,
          'line_no': lineNo++,
        });

        // Back on the shelf, at the cost it left at — which is what keeps the
        // profit on the sale and the loss on the return symmetrical.
        if (request.restock && kind != ItemKind.service && lineCost != 0) {
          if (kind == ItemKind.bundle) {
            await BundleService.receiveFor(
              txn,
              bundleItemId: line.itemId,
              qtyBundlesMilli: line.qtyBaseMilli,
              kind: 'sale_return',
              docType: 'sale_return',
              docId: returnId,
              docLineId: lineId,
              userId: request.userId,
              movedAt: stamp,
              note: invoiceNo,
            );
          } else {
            await StockService.receive(
              txn,
              itemId: line.itemId,
              qtyBaseMilli: line.qtyBaseMilli,
              unitCostMinor: line.unitCostMinor,
              kind: 'sale_return',
              docType: 'sale_return',
              docId: returnId,
              docLineId: lineId,
              userId: request.userId,
              movedAt: stamp,
              note: invoiceNo,
              // Goods coming back at the cost they left at must not move the
              // average, or a return would quietly re-price the shelf.
              updateAverage: false,
            );
          }
        }

        // The original line remembers how much of it has come back, so the
        // same goods can never be refunded twice.
        await txn.rawUpdate(
          'UPDATE sales_invoice_lines '
          '   SET returned_qty_milli = IFNULL(returned_qty_milli, 0) + ? '
          ' WHERE id = ?',
          <Object?>[line.qtyMilli, line.originLineId],
        );

        gross += lineGross;
        discount += lineDiscount;
        subtotal += taxable;
        taxTotal += tax;
        discountTaxable += lineDiscountTaxable;
        cost += lineCost;
        if (kind == ItemKind.service) {
          serviceRevenue += taxable + lineDiscountTaxable;
        } else {
          goodsRevenue += taxable + lineDiscountTaxable;
        }
      }

      final int total = subtotal + taxTotal;

      await txn.update(
        'sales_invoices',
        <String, Object?>{
          'gross_minor': gross,
          'line_discount_minor': discount,
          'discount_total_minor': discount,
          'subtotal_minor': subtotal,
          'tax_minor': taxTotal,
          'total_minor': total,
          'paid_minor': request.refundToCash ? total : 0,
          'due_minor': request.refundToCash ? 0 : total,
          'cost_minor': cost,
          'profit_minor': subtotal - cost,
          'updated_at': stamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[returnId],
      );

      if (request.refundToCash && total > 0) {
        await txn.insert('sale_tenders', <String, Object?>{
          'invoice_id': returnId,
          'method': 'cash',
          'account_id': await AppDatabase.accountIdIn(
            txn,
            request.refundAccountKey ?? AccountKeys.cash,
          ),
          'amount_minor': total,
          'direction': 'out',
        });
      }

      // ---- the postings ----------------------------------------------------
      final List<JournalLine> journal = <JournalLine>[];

      if (goodsRevenue + serviceRevenue > 0) {
        journal.add(JournalLine.debit(
          await AppDatabase.accountIdIn(txn, AccountKeys.salesReturns),
          goodsRevenue + serviceRevenue,
          memo: invoiceNo,
        ));
      }
      if (taxTotal > 0) {
        journal.add(JournalLine.debit(
          await AppDatabase.accountIdIn(txn, AccountKeys.taxPayable),
          taxTotal,
          memo: invoiceNo,
        ));
      }
      if (discountTaxable > 0) {
        journal.add(JournalLine.credit(
          await AppDatabase.accountIdIn(txn, AccountKeys.salesDiscounts),
          discountTaxable,
          memo: invoiceNo,
        ));
      }
      if (total > 0) {
        journal.add(request.refundToCash
            ? JournalLine.credit(
                await AppDatabase.accountIdIn(
                  txn,
                  request.refundAccountKey ?? AccountKeys.cash,
                ),
                total,
                memo: invoiceNo,
              )
            : JournalLine.credit(
                await partyAccount(
                    txn, request.partyId!, AccountKeys.receivable),
                total,
                partyId: request.partyId,
                memo: invoiceNo,
              ));
      }

      if (cost > 0) {
        journal.add(JournalLine.debit(
          await AppDatabase.accountIdIn(
            txn,
            // Not fit to sell again: the cost stays an expense, it just stops
            // pretending to be the cost of something that was sold.
            request.restock ? AccountKeys.inventory : AccountKeys.shrinkage,
          ),
          cost,
          memo: invoiceNo,
        ));
        journal.add(JournalLine.credit(
          await AppDatabase.accountIdIn(txn, AccountKeys.cogs),
          cost,
          memo: invoiceNo,
        ));
      }

      final int entryId = await Journal.post(
        txn,
        sourceType: 'sale_return',
        sourceId: returnId,
        entryDate: stamp.substring(0, 10),
        memo: 'Return $invoiceNo',
        userId: request.userId,
        shiftId: shiftId,
        lines: journal,
      );

      await txn.update(
        'sales_invoices',
        <String, Object?>{'journal_entry_id': entryId},
        where: 'id = ?',
        whereArgs: <Object?>[returnId],
      );

      await _refreshReturnStatus(txn, request.originInvoiceId, stamp);

      await Audit.write(
        txn,
        action: Audit.saleReturn,
        entity: 'sales_invoice',
        entityId: returnId,
        userId: request.userId,
        shiftId: shiftId,
        detail: '$invoiceNo · ${request.originInvoiceId} · $total',
      );

      return PostedSale(
        invoiceId: returnId,
        invoiceNo: invoiceNo,
        journalEntryId: entryId,
        issuedAt: stamp,
        totalMinor: total,
        changeMinor: 0,
      );
    });
  }

  /// Marks the original invoice as fully or partly returned.
  Future<void> _refreshReturnStatus(
    DatabaseExecutor txn,
    int invoiceId,
    String stamp,
  ) async {
    final List<Map<String, Object?>> rows = await txn.rawQuery(
      '''
      SELECT SUM(qty_milli)                     AS sold,
             SUM(IFNULL(returned_qty_milli, 0)) AS returned
        FROM sales_invoice_lines
       WHERE invoice_id = ?
      ''',
      <Object?>[invoiceId],
    );
    final int sold = (rows.first['sold'] as num?)?.toInt() ?? 0;
    final int returned = (rows.first['returned'] as num?)?.toInt() ?? 0;

    final String status = returned <= 0
        ? 'posted'
        : returned >= sold
            ? 'returned'
            : 'partially_returned';

    await txn.update(
      'sales_invoices',
      <String, Object?>{'status': status, 'updated_at': stamp},
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
    );
  }

  // ------------------------------------------------------------- voiding ---

  Future<void> voidSale({required int invoiceId, int? userId}) async {
    await _database.transaction<void>((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const AppFailure.notFound('That invoice no longer exists.');
      }
      final Map<String, Object?> invoice = rows.first;
      if ('${invoice['status']}' == 'void') {
        throw const AppFailure.conflict('That invoice is already cancelled.');
      }

      // A receipt has already been written against it. Cancelling the invoice
      // would leave the payment pointing at nothing, so the payment has to be
      // undone first — by a person who knows why it was taken.
      final List<Map<String, Object?>> allocated = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM payment_allocations '
        " WHERE doc_type = 'sale' AND doc_id = ?",
        <Object?>[invoiceId],
      );
      if ((allocated.first['n'] as int? ?? 0) > 0) {
        throw const AppFailure.conflict(
          'A receipt has been applied to this invoice. Cancel the receipt '
          'first.',
        );
      }

      final List<Map<String, Object?>> returned = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM sales_invoices WHERE return_of_id = ?',
        <Object?>[invoiceId],
      );
      if ((returned.first['n'] as int? ?? 0) > 0) {
        throw const AppFailure.conflict(
          'Part of this invoice has already been returned.',
        );
      }

      final String stamp = Time.stamp();
      final bool isReturn = '${invoice['doc_type']}' == 'sale_return';

      final List<Map<String, Object?>> lines = await txn.query(
        'sales_invoice_lines',
        where: 'invoice_id = ?',
        whereArgs: <Object?>[invoiceId],
        orderBy: 'line_no',
      );
      final Map<int, ItemKind> kinds = await _kindsOf(
        txn,
        lines.map((Map<String, Object?> l) => l['item_id'] as int).toList(),
      );

      for (final Map<String, Object?> line in lines) {
        final int itemId = line['item_id'] as int;
        final ItemKind kind = kinds[itemId] ?? ItemKind.stock;
        if (kind == ItemKind.service) continue;

        final int qty = line['qty_base_milli'] as int? ?? 0;
        final int unitCost = line['unit_cost_minor'] as int? ?? 0;
        if (qty <= 0) continue;

        // Cancelling a sale puts the goods back; cancelling a return takes them
        // out again. Both at the cost recorded on the line, never at today's.
        if (isReturn) {
          if (kind == ItemKind.bundle) {
            await BundleService.issueFor(
              txn,
              bundleItemId: itemId,
              qtyBundlesMilli: qty,
              kind: 'adjustment',
              docType: 'void',
              docId: invoiceId,
              userId: userId,
              movedAt: stamp,
              note: '${invoice['invoice_no']}',
              allowNegativeOverride: true,
            );
          } else {
            await StockService.issue(
              txn,
              itemId: itemId,
              qtyBaseMilli: qty,
              kind: 'adjustment',
              unitCostOverrideMinor: unitCost,
              docType: 'void',
              docId: invoiceId,
              userId: userId,
              movedAt: stamp,
              note: '${invoice['invoice_no']}',
              allowNegativeOverride: true,
            );
          }
        } else {
          if (kind == ItemKind.bundle) {
            await BundleService.receiveFor(
              txn,
              bundleItemId: itemId,
              qtyBundlesMilli: qty,
              kind: 'adjustment',
              docType: 'void',
              docId: invoiceId,
              userId: userId,
              movedAt: stamp,
              note: '${invoice['invoice_no']}',
            );
          } else {
            await StockService.receive(
              txn,
              itemId: itemId,
              qtyBaseMilli: qty,
              unitCostMinor: unitCost,
              kind: 'adjustment',
              docType: 'void',
              docId: invoiceId,
              userId: userId,
              movedAt: stamp,
              note: '${invoice['invoice_no']}',
              updateAverage: false,
            );
          }
        }
      }

      final int? entryId = invoice['journal_entry_id'] as int?;
      final int? shiftId = await ShiftService.openShiftId(txn, userId: userId);

      if (entryId != null) {
        await Journal.reverse(
          txn,
          entryId,
          memo: 'Void ${invoice['invoice_no']}',
          userId: userId,
          shiftId: shiftId,
        );
      }

      await txn.update(
        'sales_invoices',
        <String, Object?>{'status': 'void', 'updated_at': stamp},
        where: 'id = ?',
        whereArgs: <Object?>[invoiceId],
      );

      // A cancelled return releases the quantities it had claimed.
      final int? originId = invoice['return_of_id'] as int?;
      if (originId != null) {
        for (final Map<String, Object?> line in lines) {
          final int? origin = line['origin_line_id'] as int?;
          if (origin == null) continue;
          await txn.rawUpdate(
            'UPDATE sales_invoice_lines '
            '   SET returned_qty_milli = MAX(IFNULL(returned_qty_milli,0) - ?, 0) '
            ' WHERE id = ?',
            <Object?>[line['qty_milli'], origin],
          );
        }
        await _refreshReturnStatus(txn, originId, stamp);
      }

      await LoyaltyService.reverseForSale(
        txn,
        invoiceId: invoiceId,
        userId: userId,
      );

      await Audit.write(
        txn,
        action: Audit.saleVoid,
        entity: 'sales_invoice',
        entityId: invoiceId,
        userId: userId,
        shiftId: shiftId,
        detail: '${invoice['invoice_no']}',
      );
    });
  }

  // ------------------------------------------------------------- reading ---

  Future<List<SaleInvoice>> recent({int limit = 20}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_sales_invoices_full',
      orderBy: 'issued_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(SaleInvoice.fromMap).toList();
  }

  Future<List<SaleInvoice>> search(SalesQuery query) async {
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
      where.write(' AND (invoice_no LIKE ? OR party_name LIKE ?)');
      args
        ..add('%$q%')
        ..add('%$q%');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_sales_invoices_full',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'issued_at DESC, id DESC',
    );
    return rows.map(SaleInvoice.fromMap).toList();
  }

  Future<SaleInvoiceDetail> detail(int invoiceId) async {
    final List<Map<String, Object?>> head = await _database.db.query(
      'v_sales_invoices_full',
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
      limit: 1,
    );
    if (head.isEmpty) {
      throw const AppFailure.notFound('That invoice no longer exists.');
    }

    return SaleInvoiceDetail(
      invoice: SaleInvoice.fromMap(head.first),
      lines: await _linesOf(invoiceId),
      tenders: (await _database.db.query(
        'sale_tenders',
        where: 'invoice_id = ?',
        whereArgs: <Object?>[invoiceId],
      ))
          .map(SaleTender.fromMap)
          .toList(),
    );
  }

  Future<List<SaleInvoiceLine>> returnableLines(int invoiceId) async {
    final List<SaleInvoiceLine> lines = await _linesOf(invoiceId);
    return lines
        .where((SaleInvoiceLine l) => l.returnableQtyMilli > 0)
        .toList(growable: false);
  }

  Future<List<SaleInvoiceLine>> _linesOf(int invoiceId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT l.*,
             CASE WHEN i.variant_name IS NULL OR i.variant_name = ''
                  THEN i.name
                  ELSE i.name || ' — ' || i.variant_name END AS item_name,
             i.sku
        FROM sales_invoice_lines l
        JOIN items i ON i.id = l.item_id
       WHERE l.invoice_id = ?
       ORDER BY l.line_no
      ''',
      <Object?>[invoiceId],
    );
    return rows.map(SaleInvoiceLine.fromMap).toList();
  }

  // ---------------------------------------------------------------- bits ---

  Future<Map<int, ItemKind>> _kindsOf(
    DatabaseExecutor db,
    List<int> itemIds,
  ) async {
    if (itemIds.isEmpty) return <int, ItemKind>{};
    final Set<int> unique = itemIds.toSet();
    final String placeholders =
        List<String>.filled(unique.length, '?').join(', ');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT id, kind FROM items WHERE id IN ($placeholders)',
      unique.toList(),
    );
    return <int, ItemKind>{
      for (final Map<String, Object?> r in rows)
        r['id'] as int: ItemKind.fromDb(r['kind']),
    };
  }

  /// Which account a tender lands in.
  ///
  /// Cash in another currency has its own drawer account, valued in the shop's
  /// currency — mixing the two would make both counts meaningless. Cards and
  /// bank transfers are settled by the bank in the shop's currency whatever
  /// the customer's card was issued in, so they are unaffected.
  static String _tenderAccountKey(TenderInput tender) {
    // Points spent are a voucher tender marked as such. They are not money in
    // a drawer: the sale is still a sale at full price, and what the scheme
    // cost the shop lands on its own expense line.
    if (tender.method == TenderMethod.voucher &&
        (tender.reference ?? '').startsWith('points')) {
      return AccountKeys.loyaltyRedeemed;
    }
    return tender.isForeign && tender.method == TenderMethod.cash
        ? AccountKeys.cashForeign
        : _keyForTender(tender.method);
  }

  static String _keyForTender(TenderMethod method) => switch (method) {
        TenderMethod.cash => AccountKeys.cash,
        TenderMethod.card => AccountKeys.card,
        TenderMethod.bank => AccountKeys.bank,
        TenderMethod.voucher => AccountKeys.cash,
        TenderMethod.credit => AccountKeys.receivable,
      };

  /// A party's own sub-account, created on demand under receivables or
  /// payables so every customer and supplier has a real ledger of their own.
  static Future<int> partyAccount(
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
      throw AppFailure.notFound('Customer $partyId no longer exists.');
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
