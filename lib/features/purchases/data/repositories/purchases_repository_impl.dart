import 'package:dartz/dartz.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/calc/purchase_calculator.dart';
import '../../../../core/error/guard.dart';
import '../../domain/entities/purchase_document.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../datasources/purchases_local_datasource.dart';

class PurchasesRepositoryImpl implements PurchasesRepository {
  const PurchasesRepositoryImpl(this._local);

  final PurchasesLocalDataSource _local;

  @override
  Future<Result<PostedPurchase>> postPurchase({
    required PurchaseTotals totals,
    required int partyId,
    int? userId,
    String paymentMethodKey = AccountKeys.cash,
    String? supplierRef,
    String? note,
    DateTime? issuedAt,
    bool updateSellPrices = true,
    int? orderId,
  }) =>
      guard(() => _local.postPurchase(
            totals: totals,
            partyId: partyId,
            userId: userId,
            paymentMethodKey: paymentMethodKey,
            supplierRef: supplierRef,
            note: note,
            issuedAt: issuedAt,
            updateSellPrices: updateSellPrices,
            orderId: orderId,
          ));

  @override
  Future<Result<PostedPurchase>> postReturn(PurchaseReturnRequest request) =>
      guard(() => _local.postReturn(request));

  @override
  Future<Result<Unit>> voidPurchase({required int invoiceId, int? userId}) =>
      guardVoid(() => _local.voidPurchase(invoiceId: invoiceId, userId: userId));

  @override
  Future<Result<List<PurchaseInvoice>>> search(PurchasesQuery query) =>
      guard(() => _local.search(query));

  @override
  Future<Result<PurchaseInvoiceDetail>> detail(int invoiceId) =>
      guard(() => _local.detail(invoiceId));

  @override
  Future<Result<List<PurchaseInvoiceLine>>> returnableLines(int invoiceId) =>
      guard(() => _local.returnableLines(invoiceId));
}
