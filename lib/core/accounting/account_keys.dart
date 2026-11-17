/// The stable names the code uses to find accounts.
///
/// A posting never mentions an account id or an account name — it asks for a
/// key, and the chart of accounts answers. Rename "Cash box" to "Main till" and
/// every sale still posts to the right place.
class AccountKeys {
  const AccountKeys._();

  static const String cash = 'cash';


  static const String cashForeign = 'cash_usd';

  static const String bank = 'bank';
  static const String card = 'card';
  static const String receivable = 'ar';
  static const String payable = 'ap';
  static const String inventory = 'inventory';
  static const String taxPayable = 'tax_payable';

  static const String capital = 'capital';
  static const String drawings = 'drawings';
  static const String retainedEarnings = 'retained_earnings';
  static const String openingEquity = 'opening_equity';

  static const String sales = 'sales';
  static const String salesReturns = 'sales_returns';
  static const String salesDiscounts = 'sales_discounts';
  static const String serviceRevenue = 'service_revenue';
  static const String rounding = 'rounding';

  static const String cogs = 'cogs';
  static const String shrinkage = 'shrinkage';


  static const String cashOverShort = 'cash_over_short';
  static const String fxDifference = 'fx_difference';

  static const String gifts = 'gifts';
  static const String loyaltyRedeemed = 'loyalty_redeemed';
  static const String purchaseFees = 'purchase_fees';
  static const String salaries = 'salaries';
  static const String rent = 'rent';
  static const String utilities = 'utilities';
  static const String generalExpense = 'general_expense';
}
