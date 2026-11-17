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

abstract class SalesRepository {
  //? The repository is responsible for posting sales and returns, and for retrieving invoices and their details.
  //? It does not handle the business logic of calculating totals or validating tenders; 
  //? that is the responsibility of the domain layer.
  Future<Result<PostedSale>> postSale({
    required SaleTotals totals,
    required List<TenderInput> tenders,
    int? partyId,
    int? userId,
    PriceMode priceMode = PriceMode.retail,
    String? note,
    DateTime? issuedAt,
    int pointsSpent,
  });

//? Posts a return, which is a mirror of the original sale with negative quantities and amounts.
  Future<Result<PostedSale>> postReturn(SaleReturnRequest request);
//? Marks the invoice as voided, so it can no longer be used for returns or accounting.
  Future<Result<Unit>> voidSale({required int invoiceId, int? userId});
//? Marks the invoice as unVoided, so it can be used for returns and accounting again.
  Future<Result<List<SaleInvoice>>> recent({int limit = 20});
//? Searches for invoices matching the query, which can include date ranges, party IDs, and other criteria.
  Future<Result<List<SaleInvoice>>> search(SalesQuery query);
//? Retrieves the details of a specific invoice, including its lines and totals.
  Future<Result<SaleInvoiceDetail>> detail(int invoiceId);
//? Retrieves the lines of a specific invoice, which can be used to display the items sold or returned.
  Future<Result<List<SaleInvoiceLine>>> returnableLines(int invoiceId);
}
