import 'dart:async';

import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/calc/discount.dart';
import '../../../../core/calc/promotions.dart';
import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/display/customer_display.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/money/money.dart';
import '../../../../core/security/permissions.dart';
import '../../../../core/state/app_status.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../parties/domain/entities/party.dart';
import '../../../parties/domain/repositories/parties_repository.dart';
import '../../../printing/domain/repositories/printing_repository.dart';
import '../../../sales/domain/repositories/sales_repository.dart';
import '../../../shifts/domain/entities/shift.dart';
import '../../../promotions/promotions_feature.dart';
import '../../../shifts/shifts_injection.dart';
import '../../domain/entities/pos_line.dart';
import '../../domain/repositories/pos_repository.dart';
import 'pos_state.dart';

sealed class PosPrompt {
  const PosPrompt();
}

class VariantPrompt extends PosPrompt {
  const VariantPrompt(this.group, this.variants);

  final Item group;
  final List<Item> variants;
}

class WeighPrompt extends PosPrompt {
  const WeighPrompt(this.item, this.unit);

  final Item item;
  final ItemUnit? unit;
}

class PosCubit extends Cubit<PosState> {
  PosCubit({
    required CatalogRepository catalog,
    required SalesRepository sales,
    required PartiesRepository parties,
    required PosRepository pos,
    required PrintingRepository printing,
    required ShiftsRepository shifts,
    required PromotionsRepository promotions,
    int? userId,
    UserRole? role,
  })  : _catalog = catalog,
        _sales = sales,
        _parties = parties,
        _pos = pos,
        _printing = printing,
        _shifts = shifts,
        _promotions = promotions,
        _userId = userId,
        _role = role,
        super(const PosState());

  final CatalogRepository _catalog;
  final SalesRepository _sales;
  final PartiesRepository _parties;
  final PosRepository _pos;
  final PrintingRepository _printing;

  //? The till needs the drawer for two things: refusing a sale when no shift is open, and knowing today's exchange rate.
  final ShiftsRepository _shifts;

  //? Offers are read once when the till opens: a basket of twenty items must not ask the database twenty times for a list that changes twice a month.
  final PromotionsRepository _promotions;

  final int? _userId;

  //? Who is at the till
  final UserRole? _role;

  //? Whether the shop wants the floor price enforced at all.
  bool get _enforceMinPrice => state.config.enforceMinPrice;

  Timer? _debounce;
  int _searchToken = 0;

  /// Prompts the screen has to answer — a variant picker, a weight. A stream
  /// rather than state, because these are events: the same product scanned
  /// twice has to ask twice.
  final StreamController<PosPrompt> _prompts =
      StreamController<PosPrompt>.broadcast();

  Stream<PosPrompt> get prompts => _prompts.stream;

  @override
  Future<void> close() {
    _debounce?.cancel();
    _prompts.close();
    return super.close();
  }

  @override
  void onChange(Change<PosState> change) {
    super.onChange(change);
    if (!CustomerDisplay.instance.isRunning) return;

    final PosState next = change.nextState;
    if (next.lines.isEmpty) {
      CustomerDisplay.instance.show(const CustomerView());
      return;
    }

    final SaleTotals totals = next.totals;
    CustomerDisplay.instance.show(CustomerView(
      lines: <CustomerLine>[
        for (int i = 0; i < next.lines.length; i++)
          CustomerLine(
            name: next.lines[i].item.displayName,
            qty: Fmt.qty(next.lines[i].qty),
            price: Fmt.money(next.lines[i].unitPrice),
            total: Fmt.money(Money(totals.lines[i].totalMinor)),
          ),
      ],
      discount: totals.discountTotalMinor == 0
          ? ''
          : Fmt.money(Money(totals.discountTotalMinor)),
      total: Fmt.money(Money(totals.totalMinor)),
    ));
  }

  //? -- loading --

  Future<void> load() async {
    emit(state.copyWith(
      status: AppStatus.loading,
      config: _pos.config(),
      priceMode: _pos.config().defaultPriceMode,
      mayOverrideCredit:
          Permissions.instance.can(_role, Perm.posOverCreditLimit),
    ));

    final Result<List<Item>> items = await _searchItems();
    final Result<List<Category>> categories = await _catalog.categories();
    final Result<List<Party>> customers =
        await _parties.search(kind: PartyKind.customer);
    final Result<List<SaleInvoice>> recent = await _sales.recent(limit: 12);
    final Result<List<HeldCart>> held = await _pos.heldCarts();
    final Result<CashShift?> shift = await _shifts.current(userId: _userId);
    final Result<List<Promotion>> offers = await _promotions.activeToday();
    if (isClosed) return;

    final Failure? failure = firstFailure(<Result<Object?>>[items, categories]);
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    emit(state.copyWith(
      status: AppStatus.ready,
      results: items.valueOrNull,
      categories: categories.valueOrNull,
      customers: customers.valueOr(const <Party>[]),
      recentSales: recent.valueOr(const <SaleInvoice>[]),
      heldCarts: held.valueOr(const <HeldCart>[]),
      fx: _shifts.fx,
      shiftsRequired: _shifts.shiftsRequired,
      shiftOpen: shift.valueOrNull != null,
      promotions: PromotionEngine(offers.valueOr(const <Promotion>[])),
      loyalty: _promotions.loyaltyRules,
      clearFailure: true,
    ));
  }

  //? Re-prices every line against the current offers.
  List<PosLine> _priced(List<PosLine> lines) {
    if (state.promotions.isEmpty) {
      return <PosLine>[
        for (final PosLine l in lines)
          l.hasPromotion
              ? l.copyWith(
                  clearPromotion: true, discount: const DiscountSpec.none())
              : l,
      ];
    }

    final bool isMember = state.customer != null;
    return <PosLine>[
      for (final PosLine l in lines)
        if (l.isGift || (!l.discount.isEmpty && !l.hasPromotion))
          l
        else
          _priceLine(l, isMember),
    ];
  }

  PosLine _priceLine(PosLine line, bool isMember) {
    final PromotionOutcome? offer = state.promotions.bestFor(
      itemId: line.item.id,
      categoryId: line.item.categoryId,
      qtyMilli: line.qty.milli,
      unitPriceMinor: line.unitPrice.minor,
      mode: state.priceMode,
      isMember: isMember,
    );

    if (offer == null || offer.isNothing) {
      return line.hasPromotion
          ? line.copyWith(
              clearPromotion: true,
              discount: const DiscountSpec.none(),
            )
          : line;
    }

    return line.copyWith(
      discount: DiscountSpec.amountMinor(offer.discountMinor),
      promotionId: offer.promotionId,
      promotionName: offer.name,
      promotionFreeMilli: offer.freeQtyMilli,
    );
  }

  //? Called when the cashier comes back from opening a drawer, so the till unlocks without reloading the whole grid.
  Future<void> refreshShift() async {
    final Result<CashShift?> shift = await _shifts.current(userId: _userId);
    if (isClosed) return;
    emit(state.copyWith(
      shiftOpen: shift.valueOrNull != null,
      shiftsRequired: _shifts.shiftsRequired,
      fx: _shifts.fx,
    ));
  }

  //? refresh items:
  Future<Result<List<Item>>> _searchItems() => _catalog.searchItems(
        text: state.query,
        categoryId: state.categoryId,
        includeVariants: false,
        limit: 300,
      );
  //? refresh Grid:
  Future<void> _refreshGrid() async {
    final int token = ++_searchToken;
    emit(state.copyWith(searching: true));
    final Result<List<Item>> items = await _searchItems();
    if (isClosed || token != _searchToken) return;

    emit(state.copyWith(
      searching: false,
      results: items.valueOr(state.results),
      failure: items.failureOrNull,
    ));
  }
  //? refresh after sale:
  Future<void> refreshAfterSale() async {
    final Result<List<Item>> items = await _searchItems();
    final Result<List<SaleInvoice>> recent = await _sales.recent(limit: 12);
    if (isClosed) return;
    emit(state.copyWith(
      results: items.valueOr(state.results),
      recentSales: recent.valueOr(state.recentSales),
    ));
  }

  //? -- searching --
  void search(String text) {
    emit(state.copyWith(query: text));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _refreshGrid);
  }

  void selectCategory(int? categoryId) {
    emit(categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId));
    _refreshGrid();
  }
  //? submit scan:
  Future<void> submitScan(String code) async {
    final String text = code.trim();
    if (text.isEmpty) return;

    final Result<BarcodeHit?> hit = await _catalog.resolveScan(text);
    if (isClosed) return;

    final BarcodeHit? found = hit.valueOrNull;
    if (found != null) {
      await addItem(found.item, unit: found.unit, qty: found.qty);
      clearSearch();
      return;
    }

    await _refreshGrid();
    if (isClosed) return;
    if (state.results.length == 1) {
      await addItem(state.results.first);
      clearSearch();
    }
  }

  void clearSearch() {
    emit(state.copyWith(query: ''));
    _refreshGrid();
  }

  //? -- cart --

  Future<void> addItem(
    Item item, {
    ItemUnit? unit,
    Qty? qty,
    bool gift = false,
  }) async {
    Item full = item;

    if (full.isGroup) {
      final Result<List<Item>> variants = await _catalog.variantsOf(full.id);
      if (isClosed) return;
      final List<Item> list = variants.valueOr(const <Item>[]);
      if (list.isEmpty) {
        emit(state.copyWith(
          failure: const ValidationFailure(
            detail: 'This product has no variants set up yet.',
          ),
        ));
        return;
      }
      _prompts.add(VariantPrompt(full, list));
      return;
    }

    if (full.units.isEmpty) {
      final Result<Item?> loaded = await _catalog.itemById(full.id);
      if (isClosed) return;
      full = loaded.valueOrNull ?? full;
    }

    final ItemUnit? chosen = unit ?? full.saleUnit;
    if (chosen == null) {
      emit(state.copyWith(
        failure: ValidationFailure(
          detail: '"${full.displayName}" has no unit or price yet.',
        ),
      ));
      return;
    }

    // Sold by weight and nothing told us the weight: ask, rather than putting
    // one kilo in the cart and hoping somebody notices.
    if (full.isWeighed && qty == null) {
      _prompts.add(WeighPrompt(full, chosen));
      return;
    }

    _appendLine(full, chosen, qty ?? Qty.one, gift: gift);
  }

  void _appendLine(Item item, ItemUnit unit, Qty qty, {bool gift = false}) {
    final List<PosLine> lines = <PosLine>[...state.lines];
    final int index =
        lines.indexWhere((PosLine l) => l.matches(item, unit, gift: gift));

    if (index >= 0) {
      lines[index] = lines[index].copyWith(qty: lines[index].qty + qty);
      emit(state.copyWith(lines: _priced(lines), selectedLine: index));
    } else {
      lines.add(PosLine(
        item: item,
        unit: unit,
        qty: qty,
        unitPrice: unit.priceFor(state.priceMode),
        isGift: gift,
      ));
      emit(state.copyWith(
          lines: _priced(lines), selectedLine: lines.length - 1));
    }

    _warnIfShort(item);
  }


  void _warnIfShort(Item item) {
    if (!item.trackStock || item.allowNegative || !item.kind.movesStock) return;

    final int wanted = state.lines
        .where((PosLine l) => l.item.id == item.id)
        .fold(0, (int sum, PosLine l) => sum + l.qtyBase.milli);
    if (wanted > item.stockQtyMilli) {
      emit(state.copyWith(
        failure: ValidationFailure(
          detail: '${item.displayName}: '
              '${Qty(item.stockQtyMilli).units} ${item.baseUnitName}',
        ),
      ));
    }
  }

  void selectLine(int? index) => emit(index == null
      ? state.copyWith(clearSelectedLine: true)
      : state.copyWith(selectedLine: index));

  void setQty(int index, Qty qty) {
    if (index < 0 || index >= state.lines.length) return;
    if (qty.milli <= 0) {
      removeLine(index);
      return;
    }
    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = lines[index].copyWith(qty: qty);
    emit(state.copyWith(lines: _priced(lines)));
  }

  void bumpQty(int index, int deltaMilli) {
    if (index < 0 || index >= state.lines.length) return;
    setQty(index, Qty(state.lines[index].qty.milli + deltaMilli));
  }

  //? Changing a price is allowed, going under the item's floor is not: that
  //? floor is the shop owner telling the cashier where the margin ends.
  bool setPrice(int index, Money price) {
    if (index < 0 || index >= state.lines.length) return false;
    final PosLine line = state.lines[index];

    if (line.unit.minPrice.isPositive && price < line.unit.minPrice) {
      emit(state.copyWith(
        failure: ValidationFailure(
          detail: '${line.item.displayName} — '
              '${line.unit.minPrice.major}',
        ),
      ));
      return false;
    }

    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = line.copyWith(unitPrice: price);
    emit(state.copyWith(lines: _priced(lines), clearFailure: true));
    return true;
  }

  //? A discount the cashier typed.
  void setLineDiscount(int index, DiscountSpec discount) {
    if (index < 0 || index >= state.lines.length) return;
    if (!discount.isEmpty &&
        !Permissions.instance.can(_role, Perm.posDiscount)) {
      emit(state.copyWith(
        failure: const PermissionFailure(
          detail: 'Your account is not allowed to give a discount.',
        ),
      ));
      return;
    }

    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = lines[index].copyWith(
      discount: discount,
      clearPromotion: true,
    );
    emit(state.copyWith(lines: lines));
  }

  //? Changing a line's price by hand — refused under the item's floor unless
  //? the cashier is allowed to go there.
  bool setLinePrice(int index, Money price) {
    if (index < 0 || index >= state.lines.length) return false;
    final PosLine line = state.lines[index];

    final int floor = line.unit.minPrice.minor;
    if (_enforceMinPrice &&
        floor > 0 &&
        price.minor < floor &&
        !Permissions.instance.can(_role, Perm.posBelowMinPrice)) {
      emit(state.copyWith(
        failure: ValidationFailure(
          detail: '${line.item.displayName} · ${Money(floor).minor}',
        ),
      ));
      return false;
    }

    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = line.copyWith(unitPrice: price);
    emit(state.copyWith(lines: _priced(lines)));
    return true;
  }
  //? set line note
  void setLineNote(int index, String? note) {
    if (index < 0 || index >= state.lines.length) return;
    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = lines[index].copyWith(note: note);
    emit(state.copyWith(lines: _priced(lines)));
  }
  //? toggle gift
  void toggleGift(int index) {
    if (index < 0 || index >= state.lines.length) return;
    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = lines[index].copyWith(isGift: !lines[index].isGift);
    emit(state.copyWith(lines: _priced(lines)));
  }
  //? change unit
  void changeUnit(int index, ItemUnit unit) {
    if (index < 0 || index >= state.lines.length) return;
    final PosLine line = state.lines[index];
    final List<PosLine> lines = <PosLine>[...state.lines];
    lines[index] = line.copyWith(
      unit: unit,
      unitPrice: unit.priceFor(state.priceMode),
    );
    emit(state.copyWith(lines: _priced(lines)));
  }
//? remove line:
  void removeLine(int index) {
    if (index < 0 || index >= state.lines.length) return;
    final List<PosLine> lines = <PosLine>[...state.lines]..removeAt(index);
    emit(state.copyWith(
      lines: lines,
      selectedLine:
          lines.isEmpty ? null : (index - 1).clamp(0, lines.length - 1),
      clearSelectedLine: lines.isEmpty,
    ));
  }

  void clearCart() => emit(state.copyWith(
        lines: const <PosLine>[],
        invoiceDiscount: const DiscountSpec.none(),
        serviceChargeMinor: 0,
        clearCustomer: true,
        clearSelectedLine: true,
        clearFailure: true,
        clearLastSale: true,
      ));

  Future<void> setCustomer(Party? party) async {
    emit(party == null
        ? state.copyWith(
            clearCustomer: true,
            pointsBalance: 0,
            pointsToSpend: 0,
          )
        : state.copyWith(customer: party, pointsToSpend: 0));
    emit(state.copyWith(lines: _priced(state.lines)));

    if (party == null || !state.loyalty.enabled) return;
    final Result<int> points = await _promotions.pointsOf(party.id);
    if (isClosed) return;
    emit(state.copyWith(pointsBalance: points.valueOr(0)));
  }

  void setPointsToSpend(int points) {
    final int most = state.redeemablePoints;
    final int chosen = points < 0 ? 0 : (points > most ? most : points);
    emit(state.copyWith(pointsToSpend: chosen));
  }

  void setPriceMode(PriceMode mode) {
    final List<PosLine> lines = <PosLine>[
      for (final PosLine l in state.lines)
        l.copyWith(unitPrice: l.unit.priceFor(mode)),
    ];
    emit(state.copyWith(priceMode: mode, lines: _priced(lines)));
  }

  void setInvoiceDiscount(DiscountSpec spec) =>
      emit(state.copyWith(invoiceDiscount: spec));

  void setServiceCharge(Money amount) =>
      emit(state.copyWith(serviceChargeMinor: amount.minor));

  //? -- held carts --
  Future<void> loadHeldCarts() async {
    final Result<List<HeldCart>> held = await _pos.heldCarts();
    if (isClosed) return;
    emit(state.copyWith(heldCarts: held.valueOr(state.heldCarts)));
  }

  Future<int?> holdCart({String? label, int? userId}) async {
    if (state.lines.isEmpty) return null;
    emit(state.copyWith(busy: true, clearFailure: true));

    final Result<int> result = await _pos.hold(
      lines: state.lines,
      priceMode: state.priceMode,
      partyId: state.customer?.id,
      label: label,
      userId: userId,
      invoiceDiscountKind: state.invoiceDiscount.kind.name,
      invoiceDiscountValue: state.invoiceDiscount.value,
      serviceChargeMinor: state.serviceChargeMinor,
    );
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }

    clearCart();
    await loadHeldCarts();
    if (!isClosed) emit(state.copyWith(busy: false));
    return result.valueOrNull;
  }

  Future<void> resumeCart(int cartId) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<ResumedCart> result = await _pos.resume(cartId);
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return;
    }

    final ResumedCart cart = result.valueOrNull!;
    Party? party;
    if (cart.partyId != null) {
      final Result<Party?> found = await _parties.byId(cart.partyId!);
      party = found.valueOrNull;
    }
    if (isClosed) return;

    emit(state.copyWith(
      busy: false,
      lines: cart.lines,
      priceMode: cart.priceMode,
      customer: party,
      clearCustomer: party == null,
      invoiceDiscount: DiscountSpec.fromDb(
        cart.invoiceDiscountKind,
        cart.invoiceDiscountValue,
      ),
      serviceChargeMinor: cart.serviceChargeMinor,
      failure: cart.missingItems.isEmpty
          ? null
          : ValidationFailure(
              detail: cart.missingItems.join(', '),
            ),
    ));
    await loadHeldCarts();
  }

  Future<void> discardCart(int cartId) async {
    await _pos.discard(cartId);
    await loadHeldCarts();
  }

  //? -- checking out --

  //? Takes the money, writes the invoice, moves the stock, posts the books and
  //? prints — or does none of it. There is no half-finished sale.
  Future<PostedSale?> checkout({
    required List<TenderInput> tenders,
    String? note,
    int? userId,
    bool print = true,
  }) async {
    if (state.lines.isEmpty) return null;

    emit(state.copyWith(busy: true, clearFailure: true));

    final SaleTotals totals = state.totalsWith(tenders);
    final Party? customer = state.customer;
    if (state.blockedByCreditLimit &&
        totals.dueMinor > 0 &&
        customer != null &&
        customer.wouldExceedLimit(Money(totals.dueMinor))) {
      emit(state.copyWith(
        busy: false,
        failure: ValidationFailure(detail: customer.name),
      ));
      return null;
    }
    final Result<PostedSale> result = await _sales.postSale(
      totals: totals,
      tenders: tenders,
      partyId: state.customer?.id,
      userId: userId,
      priceMode: state.priceMode,
      note: note,
      pointsSpent: state.pointsToSpend,
    );
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }

    final PostedSale posted = result.valueOrNull!;
    clearCart();
    emit(state.copyWith(busy: false, lastSale: posted));
    await refreshAfterSale();
    if (print && state.config.autoPrint) {
      unawaited(_printing.printSale(posted.invoiceId));
    }
    return posted;
  }

  Future<bool> reprintLast() async {
    final PostedSale? last = state.lastSale;
    if (last == null) return false;
    final Result<dynamic> result = await _printing.printSale(last.invoiceId);
    return result.succeeded;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
