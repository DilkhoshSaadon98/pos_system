import '../localization/app_text.dart';
//? 
enum ItemKind {
  stock('stock', AppText.itemsKindStock, AppText.itemsKindStockHint),
  service('service', AppText.itemsKindService, AppText.itemsKindServiceHint),
  bundle('bundle', AppText.itemsKindBundle, AppText.itemsKindBundleHint),
  group('group', AppText.itemsKindGroup, AppText.itemsKindGroupHint);

  const ItemKind(this.dbValue, this.labelKey, this.hintKey);

  final String dbValue;
  final String labelKey;
  final String hintKey;

  static ItemKind fromDb(Object? value) => ItemKind.values.firstWhere(
        (ItemKind k) => k.dbValue == '$value',
        orElse: () => ItemKind.stock,
      );

  //? Does selling one of these move the shelf?
  bool get movesStock => this == ItemKind.stock || this == ItemKind.bundle;

  //? Can it be put in a cart at all? A group exists only to hold its variants.
  bool get isSellable => this != ItemKind.group;

  //? Does its revenue belong to the service account rather than to sales?
  bool get isService => this == ItemKind.service;
}

//? Retail or wholesale — which of an item's two prices the till is using.
enum PriceMode {
  retail('retail', AppText.posRetail),
  wholesale('wholesale', AppText.posWholesale);

  const PriceMode(this.dbValue, this.labelKey);

  final String dbValue;
  final String labelKey;

  static PriceMode fromDb(Object? value) => PriceMode.values.firstWhere(
        (PriceMode m) => m.dbValue == '$value',
        orElse: () => PriceMode.retail,
      );
}

//? The stock filter above the item list.
enum StockFilter {
  all(AppText.all),
  low(AppText.itemsFilterLow),
  out(AppText.itemsFilterOut),
  hidden(AppText.itemsFilterInactive);

  const StockFilter(this.labelKey);

  final String labelKey;
}

//? What a party is to the business.
enum PartyKind {
  customer('customer', AppText.partiesKindCustomer),
  supplier('supplier', AppText.partiesKindSupplier),
  both('both', AppText.partiesKindBoth),
  employee('employee', AppText.partiesKindEmployee);

  const PartyKind(this.dbValue, this.labelKey);

  final String dbValue;
  final String labelKey;

  static PartyKind fromDb(Object? value) => PartyKind.values.firstWhere(
        (PartyKind k) => k.dbValue == '$value',
        orElse: () => PartyKind.customer,
      );
}

//? The kinds of discount the user can type in, and how they are stored in the database.
enum UserRole {
  owner('owner', AppText.usersRoleOwner, AppText.usersRoleOwnerHint),
  manager('manager', AppText.usersRoleManager, AppText.usersRoleManagerHint),
  cashier('cashier', AppText.usersRoleCashier, AppText.usersRoleCashierHint),
  accountant(
      'accountant', AppText.usersRoleAccountant, AppText.usersRoleAccountantHint);

  const UserRole(this.dbValue, this.labelKey, this.hintKey);

  final String dbValue;
  final String labelKey;
  final String hintKey;

  static UserRole fromDb(Object? value) => UserRole.values.firstWhere(
        (UserRole r) => r.dbValue == '$value',
        orElse: () => UserRole.cashier,
      );

  bool get canSeeMoney => this != UserRole.cashier;
  bool get canManageUsers => this == UserRole.owner;
  bool get canManageCatalog => this == UserRole.owner || this == UserRole.manager;
  bool get canSeeBooks => this != UserRole.cashier;
  bool get canUseTill => this != UserRole.accountant;
  bool get canVoid => this == UserRole.owner || this == UserRole.manager;
}

//? The kinds of movement the stock ledger records.
enum StockMoveKind {
  opening('opening', AppText.stockKindOpening),
  purchase('purchase', AppText.stockKindPurchase),
  purchaseReturn('purchase_return', AppText.stockKindPurchaseReturn),
  sale('sale', AppText.stockKindSale),
  saleReturn('sale_return', AppText.stockKindSaleReturn),
  adjustment('adjustment', AppText.stockKindAdjustment),
  waste('waste', AppText.stockKindWaste),
  production('production', AppText.stockKindProduction);

  const StockMoveKind(this.dbValue, this.labelKey);

  final String dbValue;
  final String labelKey;

  static StockMoveKind fromDb(Object? value) => StockMoveKind.values.firstWhere(
        (StockMoveKind k) => k.dbValue == '$value',
        orElse: () => StockMoveKind.adjustment,
      );
}

//? The five account types, in the order a report reads them.
enum AccountType {
  asset('asset', AppText.acctTypeAsset),
  liability('liability', AppText.acctTypeLiability),
  equity('equity', AppText.acctTypeEquity),
  revenue('revenue', AppText.acctTypeRevenue),
  expense('expense', AppText.acctTypeExpense);

  const AccountType(this.dbValue, this.labelKey);

  final String dbValue;
  final String labelKey;

  static AccountType fromDb(Object? value) => AccountType.values.firstWhere(
        (AccountType t) => t.dbValue == '$value',
        orElse: () => AccountType.asset,
      );

  bool get isBalanceSheet => index <= 2;
  String get normalSide =>
      this == AccountType.asset || this == AccountType.expense
          ? 'debit'
          : 'credit';
}
