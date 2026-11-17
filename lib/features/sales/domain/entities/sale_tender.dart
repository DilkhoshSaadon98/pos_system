import 'package:cashier_system_v2/core/money/money.dart';
//? One tender on a saved invoice.
class SaleTender {
  const SaleTender({
    required this.method,
    required this.amount,
    this.reference,
  });

  factory SaleTender.fromMap(Map<String, Object?> m) => SaleTender(
        method: '${m['method']}',
        amount: Money.fromDb(m['amount_minor']),
        reference: m['reference'] as String?,
      );

  final String method;
  final Money amount;
  final String? reference;
}

