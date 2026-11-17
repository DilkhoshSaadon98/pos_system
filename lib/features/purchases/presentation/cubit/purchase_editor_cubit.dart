import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/calc/discount.dart';
import '../../../../core/calc/purchase_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../parties/domain/entities/party.dart';
import '../../../parties/domain/repositories/parties_repository.dart';
import '../../domain/entities/purchase_document.dart';
import '../../domain/repositories/purchases_repository.dart';

/// One line of a purchase being typed in.
class PurchaseDraftLine {
  const PurchaseDraftLine({
    required this.item,
    required this.unit,
    required this.qty,
    required this.unitCost,
    this.discount = const DiscountSpec.none(),
    this.taxRateBp = 0,
    this.newSellPrice,
    this.note,
    this.batchNo = '',
    this.expiryDate,
  });

  final Item item;
  final ItemUnit unit;
  final Qty qty;
  final Money unitCost;
  final DiscountSpec discount;
  final int taxRateBp;

  /// A new selling price to write onto the item when the invoice posts — the
  /// moment a shopkeeper actually decides one, with the new cost in front of
  /// them.
  final Money? newSellPrice;

  final String? note;

  /// The delivery's batch, for items counted that way. Left empty for
  /// everything else, which is most of what a shop buys.
  final String batchNo;
  final DateTime? expiryDate;

  bool get wantsBatch => item.trackBatches;

  Qty get qtyBase => Qty((qty.milli * unit.factorMilli) ~/ 1000);

  PurchaseDraftLine copyWith({
    ItemUnit? unit,
    Qty? qty,
    Money? unitCost,
    DiscountSpec? discount,
    int? taxRateBp,
    Money? newSellPrice,
    bool clearNewSellPrice = false,
    String? note,
    String? batchNo,
    DateTime? expiryDate,
    bool clearExpiry = false,
  }) =>
      PurchaseDraftLine(
        item: item,
        unit: unit ?? this.unit,
        qty: qty ?? this.qty,
        unitCost: unitCost ?? this.unitCost,
        discount: discount ?? this.discount,
        taxRateBp: taxRateBp ?? this.taxRateBp,
        newSellPrice:
            clearNewSellPrice ? null : (newSellPrice ?? this.newSellPrice),
        note: note ?? this.note,
        batchNo: batchNo ?? this.batchNo,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
      );

  PurchaseLineInput toInput({required int defaultTaxRateBp}) =>
      PurchaseLineInput(
        itemId: item.id,
        qtyMilli: qty.milli,
        unitCostMinor: unitCost.minor,
        itemUnitId: unit.id,
        unitName: unit.unitName,
        factorMilli: unit.factorMilli,
        discount: discount,
        taxRateBp: taxRateBp > 0 ? taxRateBp : defaultTaxRateBp,
        newSellPriceMinor: newSellPrice?.minor,
        note: note,
        batchNo: batchNo,
        expiryDate: expiryDate == null
            ? null
            : expiryDate!.toIso8601String().substring(0, 10),
      );
}

class PurchaseEditorState {
  const PurchaseEditorState({
    this.status = AppStatus.initial,
    this.suppliers = const <Party>[],
    this.supplier,
    this.lines = const <PurchaseDraftLine>[],
    this.invoiceDiscount = const DiscountSpec.none(),
    this.feesMinor = 0,
    this.paidMinor = 0,
    this.defaultTaxRateBp = 0,
    this.roundingStepMinor = 0,
    this.paymentMethodKey = AccountKeys.cash,
    this.supplierRef,
    this.note,
    this.updateSellPrices = true,
    this.busy = false,
    this.failure,
    this.posted,
  });

  final AppStatus status;
  final List<Party> suppliers;
  final Party? supplier;
  final List<PurchaseDraftLine> lines;
  final DiscountSpec invoiceDiscount;
  final int feesMinor;
  final int paidMinor;
  final int defaultTaxRateBp;
  final int roundingStepMinor;
  final String paymentMethodKey;
  final String? supplierRef;
  final String? note;
  final bool updateSellPrices;
  final bool busy;
  final Failure? failure;
  final PostedPurchase? posted;

  PurchaseCalculator get calculator =>
      PurchaseCalculator(roundingStepMinor: roundingStepMinor);

  /// Recomputed from the lines every time anything changes. Nothing on this
  /// screen keeps a running figure.
  PurchaseTotals get totals => calculator.compute(
        lines: <PurchaseLineInput>[
          for (final PurchaseDraftLine l in lines)
            l.toInput(defaultTaxRateBp: defaultTaxRateBp),
        ],
        invoiceDiscount: invoiceDiscount,
        feesMinor: feesMinor,
        defaultTaxRateBp: defaultTaxRateBp,
        paidMinor: paidMinor,
      );

  bool get canPost => lines.isNotEmpty && supplier != null;

  PurchaseEditorState copyWith({
    AppStatus? status,
    List<Party>? suppliers,
    Party? supplier,
    bool clearSupplier = false,
    List<PurchaseDraftLine>? lines,
    DiscountSpec? invoiceDiscount,
    int? feesMinor,
    int? paidMinor,
    int? defaultTaxRateBp,
    int? roundingStepMinor,
    String? paymentMethodKey,
    String? supplierRef,
    String? note,
    bool? updateSellPrices,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    PostedPurchase? posted,
  }) =>
      PurchaseEditorState(
        status: status ?? this.status,
        suppliers: suppliers ?? this.suppliers,
        supplier: clearSupplier ? null : (supplier ?? this.supplier),
        lines: lines ?? this.lines,
        invoiceDiscount: invoiceDiscount ?? this.invoiceDiscount,
        feesMinor: feesMinor ?? this.feesMinor,
        paidMinor: paidMinor ?? this.paidMinor,
        defaultTaxRateBp: defaultTaxRateBp ?? this.defaultTaxRateBp,
        roundingStepMinor: roundingStepMinor ?? this.roundingStepMinor,
        paymentMethodKey: paymentMethodKey ?? this.paymentMethodKey,
        supplierRef: supplierRef ?? this.supplierRef,
        note: note ?? this.note,
        updateSellPrices: updateSellPrices ?? this.updateSellPrices,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
        posted: posted ?? this.posted,
      );
}

/// Typing in a delivery.
///
/// The screen's job is to arrive at one number per line: what a base unit of
/// that item **really** cost, discount off and freight on. Everything else —
/// the invoice total, what is owed, the new selling price — follows from it.
class PurchaseEditorCubit extends Cubit<PurchaseEditorState> {
  PurchaseEditorCubit({
    required PurchasesRepository purchases,
    required CatalogRepository catalog,
    required PartiesRepository parties,
    required int defaultTaxRateBp,
    required int roundingStepMinor,
  })  : _purchases = purchases,
        _catalog = catalog,
        _parties = parties,
        super(PurchaseEditorState(
          defaultTaxRateBp: defaultTaxRateBp,
          roundingStepMinor: roundingStepMinor,
        ));

  final PurchasesRepository _purchases;
  final CatalogRepository _catalog;
  final PartiesRepository _parties;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));
    final Result<List<Party>> suppliers =
        await _parties.search(kind: PartyKind.supplier);
    if (isClosed) return;

    emit(state.copyWith(
      status: AppStatus.ready,
      suppliers: suppliers.valueOr(const <Party>[]),
      failure: suppliers.failureOrNull,
    ));
  }

  Future<List<Item>> lookup(String text) async {
    final Result<List<Item>> result = await _catalog.searchItems(
      text: text,
      includeVariants: true,
      // A service can be bought too — a delivery charge, a repair — but a
      // variant group cannot: you receive a size, not a shirt.
      kinds: const <ItemKind>{ItemKind.stock, ItemKind.service},
      limit: 40,
    );
    return result.valueOr(const <Item>[]);
  }

  void setSupplier(Party? supplier) => emit(supplier == null
      ? state.copyWith(clearSupplier: true)
      : state.copyWith(supplier: supplier));

  void addItem(Item item) {
    final ItemUnit? unit = item.purchaseUnit;
    if (unit == null) {
      emit(state.copyWith(
        failure: ValidationFailure(
          detail: '"${item.displayName}" has no unit or price yet.',
        ),
      ));
      return;
    }

    final int existing = state.lines.indexWhere(
      (PurchaseDraftLine l) => l.item.id == item.id && l.unit.id == unit.id,
    );
    final List<PurchaseDraftLine> lines = <PurchaseDraftLine>[...state.lines];

    if (existing >= 0) {
      lines[existing] =
          lines[existing].copyWith(qty: lines[existing].qty + Qty.one);
    } else {
      lines.add(PurchaseDraftLine(
        item: item,
        unit: unit,
        qty: Qty.one,
        // Last cost is the best guess a shop has; it is right far more often
        // than zero is, and it is always visible and editable.
        unitCost: Money(
          (item.lastCost.minor * unit.factorMilli) ~/ 1000,
        ),
        taxRateBp: item.taxRateBp,
      ));
    }
    emit(state.copyWith(lines: lines, clearFailure: true));
  }

  void updateLine(int index, PurchaseDraftLine line) {
    if (index < 0 || index >= state.lines.length) return;
    final List<PurchaseDraftLine> lines = <PurchaseDraftLine>[...state.lines];
    lines[index] = line;
    emit(state.copyWith(lines: lines));
  }

  void removeLine(int index) {
    if (index < 0 || index >= state.lines.length) return;
    emit(state.copyWith(
      lines: <PurchaseDraftLine>[...state.lines]..removeAt(index),
    ));
  }

  void setFees(Money fees) => emit(state.copyWith(feesMinor: fees.minor));

  void setPaid(Money paid) => emit(state.copyWith(paidMinor: paid.minor));

  void payAll() =>
      emit(state.copyWith(paidMinor: state.totals.totalMinor));

  void setInvoiceDiscount(DiscountSpec spec) =>
      emit(state.copyWith(invoiceDiscount: spec));

  void setPaymentMethod(String key) =>
      emit(state.copyWith(paymentMethodKey: key));

  void setSupplierRef(String value) => emit(state.copyWith(supplierRef: value));

  void setNote(String value) => emit(state.copyWith(note: value));

  void setUpdateSellPrices(bool value) =>
      emit(state.copyWith(updateSellPrices: value));

  void reset() => emit(PurchaseEditorState(
        status: AppStatus.ready,
        suppliers: state.suppliers,
        defaultTaxRateBp: state.defaultTaxRateBp,
        roundingStepMinor: state.roundingStepMinor,
      ));

  Future<PostedPurchase?> post({int? userId}) async {
    if (!state.canPost) return null;
    emit(state.copyWith(busy: true, clearFailure: true));

    final Result<PostedPurchase> result = await _purchases.postPurchase(
      totals: state.totals,
      partyId: state.supplier!.id,
      userId: userId,
      paymentMethodKey: state.paymentMethodKey,
      supplierRef: state.supplierRef,
      note: state.note,
      updateSellPrices: state.updateSellPrices,
    );
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }

    emit(PurchaseEditorState(
      status: AppStatus.ready,
      suppliers: state.suppliers,
      defaultTaxRateBp: state.defaultTaxRateBp,
      roundingStepMinor: state.roundingStepMinor,
      posted: result.valueOrNull,
    ));
    return result.valueOrNull;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
