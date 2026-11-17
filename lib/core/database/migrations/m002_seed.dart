import 'package:sqflite_common/sqlite_api.dart';

import '../../utils/security.dart';
import '../../utils/time.dart';

/// First-run content: the chart of accounts, base units, document counters,
/// settings and the owner login.
///
/// The chart of accounts is the part worth reading. Every account the code ever
/// needs to find carries a `system_key`; nothing in the app or in any view
/// refers to an account by id or by name, so the owner is free to rename or
/// re-code accounts without breaking a single posting.
Future<void> seedInitialData(DatabaseExecutor db) async {
  final String now = Time.stamp();

  Future<int> account({
    required String code,
    required String name,
    String? nameAr,
    String? nameKu,
    required String type,
    required String normalSide,
    int? parentId,
    String? systemKey,
    bool isGroup = false,
  }) {
    return db.insert('accounts', <String, Object?>{
      'code': code,
      'name': name,
      'name_ar': nameAr,
      'name_ku': nameKu,
      'type': type,
      'normal_side': normalSide,
      'parent_id': parentId,
      'system_key': systemKey,
      'is_group': isGroup ? 1 : 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ---------------------------------------------------------------- assets --
  final int assets = await account(
    code: '1',
    name: 'Assets',
    nameAr: 'الأصول',
    nameKu: 'سامانەکان',
    type: 'asset',
    normalSide: 'debit',
    isGroup: true,
  );
  await account(
    code: '1010',
    name: 'Cash box',
    nameAr: 'الصندوق',
    nameKu: 'سندوق',
    type: 'asset',
    normalSide: 'debit',
    parentId: assets,
    systemKey: 'cash',
  );
  await account(
    code: '1020',
    name: 'Bank',
    nameAr: 'المصرف',
    nameKu: 'بانک',
    type: 'asset',
    normalSide: 'debit',
    parentId: assets,
    systemKey: 'bank',
  );
  await account(
    code: '1025',
    name: 'Card / POS clearing',
    nameAr: 'حساب البطاقات',
    nameKu: 'کارت',
    type: 'asset',
    normalSide: 'debit',
    parentId: assets,
    systemKey: 'card',
  );
  await account(
    code: '1030',
    name: 'Accounts receivable',
    nameAr: 'الذمم المدينة',
    nameKu: 'قەرزی کڕیاران',
    type: 'asset',
    normalSide: 'debit',
    parentId: assets,
    systemKey: 'ar',
    isGroup: true,
  );
  await account(
    code: '1040',
    name: 'Inventory',
    nameAr: 'المخزون',
    nameKu: 'کۆگا',
    type: 'asset',
    normalSide: 'debit',
    parentId: assets,
    systemKey: 'inventory',
  );

  // ----------------------------------------------------------- liabilities --
  final int liabilities = await account(
    code: '2',
    name: 'Liabilities',
    nameAr: 'الخصوم',
    nameKu: 'بەرپرسیارێتییەکان',
    type: 'liability',
    normalSide: 'credit',
    isGroup: true,
  );
  await account(
    code: '2010',
    name: 'Accounts payable',
    nameAr: 'الذمم الدائنة',
    nameKu: 'قەرزی دابینکەران',
    type: 'liability',
    normalSide: 'credit',
    parentId: liabilities,
    systemKey: 'ap',
    isGroup: true,
  );
  await account(
    code: '2020',
    name: 'Tax payable',
    nameAr: 'ضريبة مستحقة',
    nameKu: 'باجی پێویست',
    type: 'liability',
    normalSide: 'credit',
    parentId: liabilities,
    systemKey: 'tax_payable',
  );

  // ---------------------------------------------------------------- equity --
  final int equity = await account(
    code: '3',
    name: 'Equity',
    nameAr: 'حقوق الملكية',
    nameKu: 'سەرمایە',
    type: 'equity',
    normalSide: 'credit',
    isGroup: true,
  );
  await account(
    code: '3010',
    name: 'Owner capital',
    nameAr: 'رأس المال',
    nameKu: 'سەرمایەی خاوەن',
    type: 'equity',
    normalSide: 'credit',
    parentId: equity,
    systemKey: 'capital',
  );
  await account(
    code: '3020',
    name: 'Owner drawings',
    nameAr: 'مسحوبات المالك',
    nameKu: 'دەرکردنی خاوەن',
    type: 'equity',
    normalSide: 'debit',
    parentId: equity,
    systemKey: 'drawings',
  );
  await account(
    code: '3030',
    name: 'Retained earnings',
    nameAr: 'الأرباح المحتجزة',
    nameKu: 'قازانجی پاشەکەوت',
    type: 'equity',
    normalSide: 'credit',
    parentId: equity,
    systemKey: 'retained_earnings',
  );
  await account(
    code: '3040',
    name: 'Opening balance equity',
    nameAr: 'رصيد افتتاحي',
    nameKu: 'باڵانسی سەرەتایی',
    type: 'equity',
    normalSide: 'credit',
    parentId: equity,
    systemKey: 'opening_equity',
  );

  // --------------------------------------------------------------- revenue --
  final int revenue = await account(
    code: '4',
    name: 'Revenue',
    nameAr: 'الإيرادات',
    nameKu: 'داهات',
    type: 'revenue',
    normalSide: 'credit',
    isGroup: true,
  );
  await account(
    code: '4010',
    name: 'Sales revenue',
    nameAr: 'إيرادات المبيعات',
    nameKu: 'داهاتی فرۆشتن',
    type: 'revenue',
    normalSide: 'credit',
    parentId: revenue,
    systemKey: 'sales',
  );
  // Contra-revenue accounts: normal side debit, so they subtract from revenue
  // in v_income_statement without any special-casing.
  await account(
    code: '4020',
    name: 'Sales returns',
    nameAr: 'مردودات المبيعات',
    nameKu: 'گەڕاندنەوەی فرۆش',
    type: 'revenue',
    normalSide: 'debit',
    parentId: revenue,
    systemKey: 'sales_returns',
  );
  await account(
    code: '4030',
    name: 'Sales discounts',
    nameAr: 'خصم المبيعات',
    nameKu: 'داشکاندنی فرۆش',
    type: 'revenue',
    normalSide: 'debit',
    parentId: revenue,
    systemKey: 'sales_discounts',
  );
  await account(
    code: '4040',
    name: 'Service charge',
    nameAr: 'رسوم الخدمة',
    nameKu: 'کرێی خزمەتگوزاری',
    type: 'revenue',
    normalSide: 'credit',
    parentId: revenue,
    systemKey: 'service_revenue',
  );
  await account(
    code: '4090',
    name: 'Rounding difference',
    nameAr: 'فروقات التقريب',
    nameKu: 'جیاوازی خڕکردنەوە',
    type: 'revenue',
    normalSide: 'credit',
    parentId: revenue,
    systemKey: 'rounding',
  );

  // -------------------------------------------------------------- expenses --
  final int expenses = await account(
    code: '5',
    name: 'Expenses',
    nameAr: 'المصروفات',
    nameKu: 'خەرجییەکان',
    type: 'expense',
    normalSide: 'debit',
    isGroup: true,
  );
  await account(
    code: '5010',
    name: 'Cost of goods sold',
    nameAr: 'تكلفة البضاعة المباعة',
    nameKu: 'تێچووی کاڵای فرۆشراو',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'cogs',
  );
  await account(
    code: '5020',
    name: 'Inventory shrinkage',
    nameAr: 'العجز في المخزون',
    nameKu: 'کەمبوونەوەی کۆگا',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'shrinkage',
  );
  await account(
    code: '5030',
    name: 'Gifts and samples',
    nameAr: 'هدايا وعينات',
    nameKu: 'دیاری و نموونە',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'gifts',
  );
  await account(
    code: '5040',
    name: 'Purchase fees and freight',
    nameAr: 'مصاريف الشراء والنقل',
    nameKu: 'کرێی کڕین و گواستنەوە',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'purchase_fees',
  );
  await account(
    code: '5050',
    name: 'Salaries',
    nameAr: 'الرواتب',
    nameKu: 'مووچە',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'salaries',
  );
  await account(
    code: '5060',
    name: 'Rent',
    nameAr: 'الإيجار',
    nameKu: 'کرێ',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'rent',
  );
  await account(
    code: '5070',
    name: 'Utilities',
    nameAr: 'الخدمات',
    nameKu: 'خزمەتگوزارییەکان',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'utilities',
  );
  await account(
    code: '5080',
    name: 'General expenses',
    nameAr: 'مصروفات عامة',
    nameKu: 'خەرجی گشتی',
    type: 'expense',
    normalSide: 'debit',
    parentId: expenses,
    systemKey: 'general_expense',
  );

  // ----------------------------------------------------------------- units --
  Future<void> unit(String name, String ar, String ku, String symbol,
      {bool fraction = false}) {
    return db.insert('units', <String, Object?>{
      'name': name,
      'name_ar': ar,
      'name_ku': ku,
      'symbol': symbol,
      'allow_fraction': fraction ? 1 : 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    }).then((_) {});
  }

  await unit('Piece', 'قطعة', 'دانە', 'pcs');
  await unit('Box', 'علبة', 'سندوق', 'box');
  await unit('Carton', 'كرتون', 'کارتۆن', 'ctn');
  await unit('Dozen', 'دزينة', 'دەرزەن', 'dz');
  await unit('Pack', 'باكيت', 'پاکێت', 'pk');
  await unit('Kilogram', 'كيلوغرام', 'کیلۆگرام', 'kg', fraction: true);
  await unit('Gram', 'غرام', 'گرام', 'g', fraction: true);
  await unit('Liter', 'لتر', 'لیتر', 'L', fraction: true);
  await unit('Meter', 'متر', 'مەتر', 'm', fraction: true);

  // -------------------------------------------------------------- counters --
  for (final List<String> c in <List<String>>[
    <String>['sales_invoice', 'INV'],
    <String>['sales_return', 'SRT'],
    <String>['purchase_invoice', 'PUR'],
    <String>['purchase_return', 'PRT'],
    <String>['payment', 'PAY'],
    <String>['receipt', 'RCV'],
    <String>['journal', 'JV'],
    <String>['party', 'C'],
  ]) {
    await db.insert('counters', <String, Object?>{
      'name': c[0],
      'prefix': c[1],
      'period': 'year',
      'last_value': 0,
    });
  }

  // -------------------------------------------------------------- settings --
  const Map<String, String> defaults = <String, String>{
    'business_name': 'My Store',
    'business_phone': '',
    'business_address': '',
    'currency_code': 'IQD',
    'currency_symbol': 'IQD',
    // How many decimals the user sees. Storage is always minor units.
    'currency_decimals': '0',
    // Cash totals are rounded to this step, in minor units. 25000 = 250 IQD.
    'rounding_step_minor': '0',
    'default_tax_rate_bp': '0',
    'prices_include_tax': '0',
    'allow_negative_stock': '0',
    'default_price_mode': 'retail',
    'language': 'en',
    'theme_mode': 'system',
    'pos_theme': 'dark',
    'auto_print_receipt': '1',
    'require_login': '1',
    'cart_slots': '12',
    'low_stock_warning': '1',
    'schema_notes': 'v1',
  };
  for (final MapEntry<String, String> e in defaults.entries) {
    await db.insert('settings', <String, Object?>{
      'key': e.key,
      'value': e.value,
      'updated_at': now,
    });
  }

  // ----------------------------------------------------------------- users --
  final String salt = Security.newSalt();
  await db.insert('users', <String, Object?>{
    'full_name': 'Administrator',
    'username': 'admin',
    'password_salt': salt,
    'password_hash': Security.hashPassword('admin', salt),
    'role': 'owner',
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });

  // ------------------------------------------------------- printer profile --
  await db.insert('printer_profiles', <String, Object?>{
    'name': 'Receipt 80mm',
    'driver': 'pdf',
    'paper': 'roll80',
    'copies': 1,
    'header_text': '',
    'footer_text': 'Thank you',
    'show_logo': 1,
    'show_barcode': 1,
    'show_tax_lines': 1,
    'open_drawer': 0,
    'auto_print': 1,
    'font_scale_bp': 10000,
    'is_default': 1,
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });
}
