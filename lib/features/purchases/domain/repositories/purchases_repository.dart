import 'package:dartz/dartz.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/calc/purchase_calculator.dart';
import '../../../../core/error/guard.dart';
import '../entities/purchase_document.dart';

abstract class PurchasesRepository {
  /// Writes a purchase: the invoice, its lines, one stock receipt per line at
  /// the **landed** cost, and one balanced journal entry.
  Future<Result<PostedPurchase>> postPurchase({
    required PurchaseTotals totals,
    required int partyId,
    int? userId,
    String paymentMethodKey = AccountKeys.cash,
    String? supplierRef,
    String? note,
    DateTime? issuedAt,
    bool updateSellPrices = true,

    /// The order this delivery fulfils, when it came from one.
    int? orderId,
  });

  /// Sends goods back to the supplier, at the cost they came in at.
  Future<Result<PostedPurchase>> postReturn(PurchaseReturnRequest request);

  Future<Result<Unit>> voidPurchase({required int invoiceId, int? userId});

  Future<Result<List<PurchaseInvoice>>> search(PurchasesQuery query);

  Future<Result<PurchaseInvoiceDetail>> detail(int invoiceId);

  Future<Result<List<PurchaseInvoiceLine>>> returnableLines(int invoiceId);
}
