import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_detail.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_query.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_request.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../domain/repositories/sales_repository.dart';
import '../datasources/sales_local_datasource.dart';

class SalesRepositoryImpl implements SalesRepository {
  const SalesRepositoryImpl(this._local);

  final SalesLocalDataSource _local;

  @override
  Future<Result<PostedSale>> postSale({
    required SaleTotals totals,
    required List<TenderInput> tenders,
    int? partyId,
    int? userId,
    PriceMode priceMode = PriceMode.retail,
    String? note,
    DateTime? issuedAt,
    int pointsSpent = 0,
  }) =>
      guard(() => _local.postSale(
            totals: totals,
            tenders: tenders,
            partyId: partyId,
            userId: userId,
            priceMode: priceMode,
            note: note,
            issuedAt: issuedAt,
            pointsSpent: pointsSpent,
          ));

  @override
  Future<Result<PostedSale>> postReturn(SaleReturnRequest request) =>
      guard(() => _local.postReturn(request));

  @override
  Future<Result<Unit>> voidSale({required int invoiceId, int? userId}) =>
      guardVoid(() => _local.voidSale(invoiceId: invoiceId, userId: userId));

  @override
  Future<Result<List<SaleInvoice>>> recent({int limit = 20}) =>
      guard(() => _local.recent(limit: limit));

  @override
  Future<Result<List<SaleInvoice>>> search(SalesQuery query) =>
      guard(() => _local.search(query));

  @override
  Future<Result<SaleInvoiceDetail>> detail(int invoiceId) =>
      guard(() => _local.detail(invoiceId));

  @override
  Future<Result<List<SaleInvoiceLine>>> returnableLines(int invoiceId) =>
      guard(() => _local.returnableLines(invoiceId));
}
