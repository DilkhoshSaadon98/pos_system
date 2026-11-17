import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/sale_invoices.dart';

import '../../../../core/calc/discount.dart';
import '../../../../core/calc/promotions.dart';
import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/loyalty/loyalty_service.dart';
import '../../../../core/money/fx.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../parties/domain/entities/party.dart';
import '../../domain/entities/pos_line.dart';

class PosState {
  final AppStatus status;
  final PosConfig config;

  //? Read once at sign-in, not asked of the permission table on every build.
  final bool mayOverrideCredit;
  final List<PosLine> lines;

  //? The product grid, already filtered.
  final List<Item> results;
  final List<Category> categories;
  final List<Party> customers;
  final List<HeldCart> heldCarts;
  final List<SaleInvoice> recentSales;
  final String query;
  final int? categoryId;
  final Party? customer;
  final PriceMode priceMode;
  final DiscountSpec invoiceDiscount;
  final int serviceChargeMinor;
  //? Which cart line the keypad and the quick actions apply to.
  final int? selectedLine;
  final bool busy;
  final bool searching;
  final Failure? failure;

  //? The sale just posted, so the screen can offer to print it again.
  final PostedSale? lastSale;

  final FxRate fx;
  final bool shiftsRequired;
  final bool shiftOpen;

  const PosState({
    this.status = AppStatus.initial,
    this.config = const PosConfig(),
    this.mayOverrideCredit = false,
    this.lines = const <PosLine>[],
    this.results = const <Item>[],
    this.categories = const <Category>[],
    this.customers = const <Party>[],
    this.heldCarts = const <HeldCart>[],
    this.recentSales = const <SaleInvoice>[],
    this.query = '',
    this.categoryId,
    this.customer,
    this.priceMode = PriceMode.retail,
    this.invoiceDiscount = const DiscountSpec.none(),
    this.serviceChargeMinor = 0,
    this.selectedLine,
    this.busy = false,
    this.searching = false,
    this.failure,
    this.lastSale,
    this.fx = FxRate.off,
    this.shiftsRequired = false,
    this.shiftOpen = false,
    this.promotions = PromotionEngine.none,
    this.loyalty = LoyaltyRules.off,
    this.pointsBalance = 0,
    this.pointsToSpend = 0,
  });

  bool get blockedByShift => shiftsRequired && !shiftOpen;

  //? The offers in force today, loaded once when the till opened.
  final PromotionEngine promotions;

  //? The points scheme, and what this customer has.
  final LoyaltyRules loyalty;
  final int pointsBalance;

  //? Points the cashier has chosen to spend on this bill.
  final int pointsToSpend;

  bool get canUsePoints =>
      loyalty.enabled && customer != null && pointsBalance > 0;

  //? What the chosen points take off the bill.
  int get pointsValueMinor => loyalty.valueOf(pointsToSpend);

  //? The most that could sensibly be spent on what is in the cart.
  int get redeemablePoints => loyalty.redeemableFor(
        balance: pointsBalance,
        totalMinor: totals.totalMinor,
      );

  bool get isEmpty => lines.isEmpty;

  //? The bill, recomputed from the lines every time anything changes.
  SaleTotals get totals => config.calculator.compute(
        lines: <SaleLineInput>[
          for (final PosLine l in lines)
            l.toInput(defaultTaxRateBp: config.defaultTaxRateBp),
        ],
        invoiceDiscount: invoiceDiscount,
        defaultTaxRateBp: config.defaultTaxRateBp,
        serviceChargeMinor: serviceChargeMinor,
      );

  //? The same totals with a set of tenders applied — what the payment sheet
  //? shows while the cashier is counting the money out.
  SaleTotals totalsWith(List<TenderInput> tenders) => config.calculator.compute(
        lines: <SaleLineInput>[
          for (final PosLine l in lines)
            l.toInput(defaultTaxRateBp: config.defaultTaxRateBp),
        ],
        invoiceDiscount: invoiceDiscount,
        defaultTaxRateBp: config.defaultTaxRateBp,
        serviceChargeMinor: serviceChargeMinor,
        tenders: tenders,
      );

  Money get total => Money(totals.totalMinor);

  int get unitsCount =>
      lines.fold(0, (int sum, PosLine l) => sum + l.qty.milli);

  //? Whether the till must actually stop the sale.
  bool get blockedByCreditLimit =>
      config.enforceCreditLimit && !mayOverrideCredit;

  PosState copyWith({
    AppStatus? status,
    PosConfig? config,
    bool? mayOverrideCredit,
    List<PosLine>? lines,
    List<Item>? results,
    List<Category>? categories,
    List<Party>? customers,
    List<HeldCart>? heldCarts,
    List<SaleInvoice>? recentSales,
    String? query,
    int? categoryId,
    bool clearCategory = false,
    Party? customer,
    bool clearCustomer = false,
    PriceMode? priceMode,
    DiscountSpec? invoiceDiscount,
    int? serviceChargeMinor,
    int? selectedLine,
    bool clearSelectedLine = false,
    bool? busy,
    bool? searching,
    Failure? failure,
    bool clearFailure = false,
    PostedSale? lastSale,
    bool clearLastSale = false,
    FxRate? fx,
    bool? shiftsRequired,
    bool? shiftOpen,
    PromotionEngine? promotions,
    LoyaltyRules? loyalty,
    int? pointsBalance,
    int? pointsToSpend,
  }) =>
      PosState(
        status: status ?? this.status,
        config: config ?? this.config,
        mayOverrideCredit: mayOverrideCredit ?? this.mayOverrideCredit,
        lines: lines ?? this.lines,
        results: results ?? this.results,
        categories: categories ?? this.categories,
        customers: customers ?? this.customers,
        heldCarts: heldCarts ?? this.heldCarts,
        recentSales: recentSales ?? this.recentSales,
        query: query ?? this.query,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        customer: clearCustomer ? null : (customer ?? this.customer),
        priceMode: priceMode ?? this.priceMode,
        invoiceDiscount: invoiceDiscount ?? this.invoiceDiscount,
        serviceChargeMinor: serviceChargeMinor ?? this.serviceChargeMinor,
        selectedLine:
            clearSelectedLine ? null : (selectedLine ?? this.selectedLine),
        busy: busy ?? this.busy,
        searching: searching ?? this.searching,
        failure: clearFailure ? null : (failure ?? this.failure),
        lastSale: clearLastSale ? null : (lastSale ?? this.lastSale),
        fx: fx ?? this.fx,
        shiftsRequired: shiftsRequired ?? this.shiftsRequired,
        shiftOpen: shiftOpen ?? this.shiftOpen,
        promotions: promotions ?? this.promotions,
        loyalty: loyalty ?? this.loyalty,
        pointsBalance: pointsBalance ?? this.pointsBalance,
        pointsToSpend: pointsToSpend ?? this.pointsToSpend,
      );
}
