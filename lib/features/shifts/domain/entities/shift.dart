import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/money/money.dart';

/// One cashier, one drawer, between two counts.
class CashShift {
  const CashShift({
    required this.id,
    required this.shiftNo,
    required this.openedAt,
    required this.isOpen,
    required this.openingFloat,
    required this.openingFloatFxMinor,
    required this.cashMovement,
    required this.cashFxMovement,
    required this.salesCount,
    required this.salesTotal,
    required this.salesProfit,
    required this.returnsCount,
    required this.returnsTotal,
    required this.voidsCount,
    this.userId,
    this.userName,
    this.closedAt,
    this.counted,
    this.countedFxMinor,
    this.expected,
    this.difference,
  });

  factory CashShift.fromRow(Map<String, Object?> m) => CashShift(
        id: m['shift_id'] as int,
        shiftNo: '${m['shift_no']}',
        userId: m['user_id'] as int?,
        userName: m['user_name'] as String?,
        openedAt: '${m['opened_at']}',
        closedAt: m['closed_at'] as String?,
        isOpen: '${m['status']}' == 'open',
        openingFloat: Money.fromDb(m['opening_float_minor']),
        openingFloatFxMinor: m['opening_float_fx_minor'] as int? ?? 0,
        counted: m['counted_minor'] == null
            ? null
            : Money.fromDb(m['counted_minor']),
        countedFxMinor: m['counted_fx_minor'] as int?,
        expected: m['recorded_expected_minor'] == null
            ? null
            : Money.fromDb(m['recorded_expected_minor']),
        difference: m['difference_minor'] == null
            ? null
            : Money.fromDb(m['difference_minor']),
        cashMovement: Money.fromDb(m['cash_movement_minor']),
        cashFxMovement: Money.fromDb(m['cash_fx_movement_minor']),
        salesCount: m['sales_count'] as int? ?? 0,
        salesTotal: Money.fromDb(m['sales_total_minor']),
        salesProfit: Money.fromDb(m['sales_profit_minor']),
        returnsCount: m['returns_count'] as int? ?? 0,
        returnsTotal: Money.fromDb(m['returns_total_minor']),
        voidsCount: m['voids_count'] as int? ?? 0,
      );

  final int id;
  final String shiftNo;
  final int? userId;
  final String? userName;
  final String openedAt;
  final String? closedAt;
  final bool isOpen;

  /// Counted into the drawer before the first sale.
  final Money openingFloat;
  final int openingFloatFxMinor;

  /// Counted out of it at the end, and what the books expected.
  final Money? counted;
  final int? countedFxMinor;
  final Money? expected;

  /// `counted − expected`. Negative is a shortage.
  final Money? difference;

  /// Everything that reached the cash account while this shift was open.
  final Money cashMovement;
  final Money cashFxMovement;

  final int salesCount;
  final Money salesTotal;
  final Money salesProfit;
  final int returnsCount;
  final Money returnsTotal;
  final int voidsCount;

  bool get isShort => (difference?.minor ?? 0) < 0;
  bool get isOver => (difference?.minor ?? 0) > 0;
  bool get isBalanced => (difference?.minor ?? 0) == 0;

  /// Net takings: what was sold less what was given back.
  Money get netSales => Money(salesTotal.minor - returnsTotal.minor);
}

/// One line of the tender breakdown — "cash in, 14 payments, 862,000".
class ShiftTenderRow {
  const ShiftTenderRow({
    required this.method,
    required this.isIn,
    required this.count,
    required this.amount,
    required this.amountFxMinor,
    this.currencyCode,
  });

  factory ShiftTenderRow.fromRow(Map<String, Object?> m) => ShiftTenderRow(
        method: TenderMethod.values.firstWhere(
          (TenderMethod t) => t.name == '${m['method']}',
          orElse: () => TenderMethod.cash,
        ),
        isIn: '${m['direction']}' == 'in',
        currencyCode: m['currency_code'] as String?,
        count: m['tender_count'] as int? ?? 0,
        amount: Money.fromDb(m['amount_minor']),
        amountFxMinor: m['amount_fx_minor'] as int? ?? 0,
      );

  final TenderMethod method;
  final bool isIn;

  /// Null when the money was taken in the shop's own currency.
  final String? currencyCode;

  final int count;
  final Money amount;
  final int amountFxMinor;

  bool get isForeign => currencyCode != null && currencyCode!.isNotEmpty;
}

/// Everything an X or a Z report prints.
///
/// The two are the same report: X is taken while the drawer is still open and
/// changes nothing, Z is taken as it closes and is the count of record. Making
/// them one type is deliberate — a cashier who can read the mid-shift figure
/// is not surprised by the one at the end.
class ShiftReport {
  const ShiftReport({
    required this.shift,
    required this.tenders,
    required this.expected,
    required this.expectedFxMinor,
    required this.generatedAt,
    required this.isFinal,
  });

  final CashShift shift;
  final List<ShiftTenderRow> tenders;

  /// What the drawer should hold at this instant, from the ledger.
  final Money expected;
  final int expectedFxMinor;

  final String generatedAt;

  /// True for a Z report — the shift is closed and this is the record.
  final bool isFinal;

  Iterable<ShiftTenderRow> get taken =>
      tenders.where((ShiftTenderRow t) => t.isIn);
  Iterable<ShiftTenderRow> get givenBack =>
      tenders.where((ShiftTenderRow t) => !t.isIn);

  Money totalFor(TenderMethod method) => Money(
        tenders
            .where((ShiftTenderRow t) => t.method == method)
            .fold(0, (int sum, ShiftTenderRow t) => sum + t.amount.minor),
      );
}

/// What the close screen sends back: the count, in both currencies.
class ShiftCloseRequest {
  const ShiftCloseRequest({
    required this.shiftId,
    required this.countedMinor,
    this.countedFxMinor = 0,
    this.userId,
    this.note,
  });

  final int shiftId;
  final int countedMinor;
  final int countedFxMinor;
  final int? userId;
  final String? note;
}
