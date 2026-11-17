import 'package:cashier_system_v2/core/money/money.dart';

//? What a freshly posted sale hands back to the screen that made it.
class PostedSale {
  const PostedSale({
    required this.invoiceId,
    required this.invoiceNo,
    required this.journalEntryId,
    required this.issuedAt,
    required this.totalMinor,
    required this.changeMinor,
  });

  final int invoiceId;
  final String invoiceNo;
  final int journalEntryId;
  final String issuedAt;
  final int totalMinor;
  final int changeMinor;

  Money get total => Money(totalMinor);
  Money get change => Money(changeMinor);
}
