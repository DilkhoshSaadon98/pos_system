import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoice_line.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_tender.dart';

//? An invoice with everything hanging off it — what the detail sheet, the
//? receipt and the return screen all read.
class SaleInvoiceDetail {
  const SaleInvoiceDetail({
    required this.invoice,
    required this.lines,
    required this.tenders,
  });

  final SaleInvoice invoice;
  final List<SaleInvoiceLine> lines;
  final List<SaleTender> tenders;

  bool get hasSomethingToReturn =>
      lines.any((SaleInvoiceLine l) => l.returnableQtyMilli > 0);
}
