import 'package:cashier_system_v2/features/sales/domain/entities/sale_return_line.dart';

//? Everything a return needs, gathered by the screen and posted in one go.
class SaleReturnRequest {
    final int originInvoiceId;
  final List<SaleReturnLine> lines;
  final bool refundToCash;

  final int? partyId;
  final int? userId;
  final String? reason;
  final bool restock;

  final String? refundAccountKey;
  const SaleReturnRequest({
    required this.originInvoiceId,
    required this.lines,
    required this.refundToCash,
    this.partyId,
    this.userId,
    this.reason,
    this.restock = true,
    this.refundAccountKey,
  });


}
