import 'package:sqflite_common/sqlite_api.dart';

import '../accounting/account_keys.dart';
import '../accounting/journal.dart';
import '../inventory/batch_service.dart';
import '../error/exceptions.dart';
import '../inventory/stock_service.dart';
import '../utils/audit.dart';
import '../utils/time.dart';
import 'app_database.dart';

/// One row of the test catalogue.
///
/// Money is written here in whole dinars and quantities in whole units, because
/// that is how a shopkeeper reads a price list. The seeder converts both to the
/// integer units the database actually stores, so nothing in this table has to
/// remember that a price is hundredths and a quantity is thousandths.
class TestItem {
  const TestItem(
    this.en,
    this.ar,
    this.ku,
    this.category,
    this.unit,
    this.cost,
    this.price,
    this.qty, {
    this.pack = 0,
    this.weighed = false,
    this.shelfDays = 0,
    this.reorder = 0,
  });

  final String en;
  final String ar;
  final String ku;

  /// Index into [TestCatalogue.categories].
  final int category;

  /// Base unit name, matching a row seeded in `units`.
  final String unit;

  final int cost;
  final int price;
  final int qty;

  /// Units in a carton. Zero means the item is sold in its base unit only.
  final int pack;

  final bool weighed;

  /// How long the goods keep. Anything three months or under is counted by
  /// batch, which is the rule a real shop uses: you track dates on the things
  /// that go off, not on the washing powder.
  final int shelfDays;

  final int reorder;

  bool get tracksBatches => shelfDays > 0 && shelfDays <= 90;
}

/// What the seeder put in.
class TestCatalogueReport {
  const TestCatalogueReport({
    required this.categories,
    required this.items,
    required this.barcodes,
    required this.batches,
    required this.stockValueMinor,
  });

  final int categories;
  final int items;
  final int barcodes;
  final int batches;
  final int stockValueMinor;

  bool get isEmpty => items == 0;

  List<String> get summary => <String>[
        'Categories: \$categories',
        'Items: \$items',
        'Barcodes: \$barcodes',
        'Batches: \$batches',
      ];
}

/// A supermarket's worth of test data, put into the shop's own database.
///
/// Everything here goes in through the same doors the app itself uses:
/// [StockService.receive] for the goods and one balanced [Journal] entry for
/// what they cost, so a seeded database still passes the same trial-balance
/// check an audited one does. Nothing is written straight into `stock_moves` or
/// into an account balance.
///
/// It is safe to run twice. Items are matched by SKU and categories by name, so
/// a second run adds only what is missing rather than doubling the shelves.
class TestCatalogue {
  const TestCatalogue._();

  /// Set once the shop has test data, so the button can say so.
  static const String settingKey = 'test_catalogue_loaded';

  static bool isLoaded(AppDatabase database) =>
      database.settingString(settingKey) == '1';

  /// The aisles.
  static const List<List<String>> categories = <List<String>>[
    <String>['Bakery', 'مخبوزات', 'نانەواخانە', '#C99A4A'],
    <String>['Dairy & Eggs', 'الألبان والبيض', 'شیرەمەنی و هێلکە', '#4A90D9'],
    <String>['Fruit & Vegetables', 'الخضار والفواكه', 'میوە و سەوزە', '#5BAA5B'],
    <String>['Meat & Poultry', 'اللحوم والدواجن', 'گۆشت و مریشک', '#C0504D'],
    <String>['Frozen', 'المجمدات', 'قەتیسکراو', '#4FB0C6'],
    <String>['Beverages', 'المشروبات', 'خواردنەوەکان', '#7B5EA7'],
    <String>['Snacks & Sweets', 'الحلويات والمقرمشات', 'خنجیلانە و شیرینی', '#E08A3C'],
    <String>['Grains & Pasta', 'الحبوب والمعكرونة', 'دانەوێڵە و مەکەرۆنی', '#B08D57'],
    <String>['Oils & Canned', 'الزيوت والمعلبات', 'ڕۆن و قوتوو', '#8C8C3B'],
    <String>['Spices & Sauces', 'البهارات والصلصات', 'بەهارات و سۆس', '#A0522D'],
    <String>['Cleaning', 'منظفات', 'پاککەرەوە', '#3FA9A0'],
    <String>['Personal Care', 'العناية الشخصية', 'چاودێری کەسی', '#D06A9C'],
    <String>['Baby', 'مستلزمات الأطفال', 'پێداویستی منداڵ', '#F0A6C0'],
    <String>['Household', 'أدوات منزلية', 'کەلوپەلی ماڵ', '#6E7B8B'],
    <String>['Tobacco', 'التبغ', 'جگەرە', '#6B6B6B'],
  ];

  /// The shelves.
  static const List<TestItem> items = <TestItem>[
    TestItem('Samoon Bread 5pcs', 'صمون ٥ حبات', 'نانی سەموون ٥ دانە', 0, 'Piece', 300, 500, 120, shelfDays: 3, reorder: 30),
    TestItem('Tanoor Bread', 'خبز تنور', 'نانی تەنوور', 0, 'Piece', 250, 400, 90, shelfDays: 3, reorder: 25),
    TestItem('Toast Bread 600g', 'خبز توست ٦٠٠غم', 'نانی تۆست ٦٠٠گ', 0, 'Piece', 1100, 1500, 60, pack: 12, shelfDays: 10, reorder: 15),
    TestItem('Brown Toast 500g', 'توست أسمر ٥٠٠غم', 'تۆستی قاوەیی ٥٠٠گ', 0, 'Piece', 1300, 1750, 40, pack: 12, shelfDays: 10, reorder: 10),
    TestItem('Burger Buns 6pcs', 'خبز برجر ٦ حبات', 'نانی بەرگەر ٦ دانە', 0, 'Piece', 900, 1250, 50, pack: 12, shelfDays: 7, reorder: 12),
    TestItem('Croissant Plain', 'كرواسان سادة', 'کرواسانی سادە', 0, 'Piece', 500, 750, 80, pack: 24, shelfDays: 20, reorder: 20),
    TestItem('Chocolate Croissant', 'كرواسان شوكولاتة', 'کرواسانی شۆکولات', 0, 'Piece', 600, 900, 80, pack: 24, shelfDays: 20, reorder: 20),
    TestItem('Cake Roll Vanilla', 'كيك رول فانيلا', 'کێکی ڕۆڵ ڤانیلا', 0, 'Piece', 400, 600, 100, pack: 30, shelfDays: 60, reorder: 25),
    TestItem('Donut Sugar', 'دونات بالسكر', 'دۆنەتی شەکر', 0, 'Piece', 500, 850, 45, pack: 12, shelfDays: 7, reorder: 12),
    TestItem('Baklava', 'بقلاوة', 'بەقلاوە', 0, 'Kilogram', 12000, 18000, 15, weighed: true, shelfDays: 20, reorder: 4),
    TestItem('Kleicha', 'كليجة', 'کلێچە', 0, 'Kilogram', 9000, 14000, 12, weighed: true, shelfDays: 30, reorder: 3),
    TestItem('Pita Bread 8pcs', 'خبز عربي ٨ حبات', 'نانی عەرەبی ٨ دانە', 0, 'Piece', 750, 1100, 55, pack: 10, shelfDays: 7, reorder: 15),
    TestItem('Rusk Biscuit 300g', 'بقسماط ٣٠٠غم', 'بەقسماتی ٣٠٠گ', 0, 'Piece', 1000, 1500, 40, pack: 20, shelfDays: 180, reorder: 10),
    TestItem('Birthday Cake 1kg', 'كيك عيد ميلاد ١كغ', 'کێکی ڕۆژی لەدایکبوون ١کگ', 0, 'Piece', 12000, 20000, 6, shelfDays: 4, reorder: 2),
    TestItem('Fresh Milk 1L', 'حليب طازج ١ لتر', 'شیری تازە ١ لیتر', 1, 'Piece', 1400, 1900, 90, pack: 12, shelfDays: 10, reorder: 24),
    TestItem('Full Cream Milk 1L', 'حليب كامل الدسم ١ لتر', 'شیری پڕ چەور ١ لیتر', 1, 'Piece', 1500, 2000, 80, pack: 12, shelfDays: 120, reorder: 24),
    TestItem('Low Fat Milk 1L', 'حليب قليل الدسم ١ لتر', 'شیری کەم چەور ١ لیتر', 1, 'Piece', 1500, 2000, 60, pack: 12, shelfDays: 120, reorder: 18),
    TestItem('Laban 1L', 'لبن ١ لتر', 'دۆی ١ لیتر', 1, 'Piece', 1200, 1750, 70, pack: 12, shelfDays: 14, reorder: 20),
    TestItem('Yoghurt 900g', 'لبن رائب ٩٠٠غم', 'ماستی ٩٠٠گ', 1, 'Piece', 1800, 2500, 55, pack: 6, shelfDays: 14, reorder: 15),
    TestItem('Greek Yoghurt 400g', 'زبادي يوناني ٤٠٠غم', 'ماستی یۆنانی ٤٠٠گ', 1, 'Piece', 1600, 2250, 40, pack: 12, shelfDays: 21, reorder: 12),
    TestItem('Cream Cheese 200g', 'جبنة كريمية ٢٠٠غم', 'پەنیری کرێمی ٢٠٠گ', 1, 'Piece', 2200, 3000, 45, pack: 24, shelfDays: 120, reorder: 12),
    TestItem('Triangle Cheese 8pcs', 'جبنة مثلثات ٨ حبات', 'پەنیری سێگۆشە ٨ دانە', 1, 'Piece', 1900, 2750, 60, pack: 24, shelfDays: 180, reorder: 15),
    TestItem('Cheddar Slices 200g', 'جبنة شرائح ٢٠٠غم', 'پەنیری چدەر پارچە ٢٠٠گ', 1, 'Piece', 2600, 3500, 40, pack: 20, shelfDays: 120, reorder: 12),
    TestItem('White Cheese 500g', 'جبنة بيضاء ٥٠٠غم', 'پەنیری سپی ٥٠٠گ', 1, 'Piece', 3400, 4500, 35, pack: 12, shelfDays: 90, reorder: 10),
    TestItem('Local Cheese', 'جبن محلي', 'پەنیری ناوخۆیی', 1, 'Kilogram', 9000, 13000, 18, weighed: true, shelfDays: 30, reorder: 5),
    TestItem('Butter 200g', 'زبدة ٢٠٠غم', 'کەرەی ٢٠٠گ', 1, 'Piece', 2800, 3750, 30, pack: 24, shelfDays: 180, reorder: 10),
    TestItem('Table Eggs 30pcs', 'بيض مائدة ٣٠ حبة', 'هێلکەی ٣٠ دانە', 1, 'Piece', 5500, 7000, 40, shelfDays: 21, reorder: 10),
    TestItem('Table Eggs 6pcs', 'بيض ٦ حبات', 'هێلکەی ٦ دانە', 1, 'Piece', 1200, 1750, 50, shelfDays: 21, reorder: 15),
    TestItem('Cooking Cream 250ml', 'قشطة طبخ ٢٥٠مل', 'کرێمی چێشتلێنان ٢٥٠مل', 1, 'Piece', 1500, 2100, 45, pack: 24, shelfDays: 180, reorder: 12),
    TestItem('Labneh 500g', 'لبنة ٥٠٠غم', 'لەبەنەی ٥٠٠گ', 1, 'Piece', 3000, 4000, 30, pack: 12, shelfDays: 45, reorder: 8),
    TestItem('Tomato', 'طماطة', 'تەماتە', 2, 'Kilogram', 1000, 1500, 120, weighed: true, shelfDays: 10, reorder: 30),
    TestItem('Cucumber', 'خيار', 'خەیار', 2, 'Kilogram', 1200, 1750, 90, weighed: true, shelfDays: 10, reorder: 25),
    TestItem('Potato', 'بطاطا', 'پەتاتە', 2, 'Kilogram', 900, 1250, 150, weighed: true, shelfDays: 30, reorder: 40),
    TestItem('Onion', 'بصل', 'پیاز', 2, 'Kilogram', 800, 1200, 140, weighed: true, shelfDays: 45, reorder: 40),
    TestItem('Garlic', 'ثوم', 'سیر', 2, 'Kilogram', 4000, 6000, 25, weighed: true, shelfDays: 60, reorder: 8),
    TestItem('Carrot', 'جزر', 'گێزەر', 2, 'Kilogram', 1100, 1600, 60, weighed: true, shelfDays: 21, reorder: 20),
    TestItem('Eggplant', 'باذنجان', 'باینجان', 2, 'Kilogram', 1000, 1500, 55, weighed: true, shelfDays: 14, reorder: 18),
    TestItem('Green Pepper', 'فلفل أخضر', 'بیبەری سەوز', 2, 'Kilogram', 1800, 2500, 45, weighed: true, shelfDays: 12, reorder: 15),
    TestItem('Lettuce', 'خس', 'خەس', 2, 'Piece', 750, 1250, 40, shelfDays: 7, reorder: 12),
    TestItem('Parsley Bunch', 'بقدونس', 'جەعدە', 2, 'Piece', 250, 500, 50, shelfDays: 5, reorder: 15),
    TestItem('Banana', 'موز', 'مۆز', 2, 'Kilogram', 2200, 3000, 80, weighed: true, shelfDays: 7, reorder: 20),
    TestItem('Apple Red', 'تفاح أحمر', 'سێوی سوور', 2, 'Kilogram', 2500, 3500, 70, weighed: true, shelfDays: 30, reorder: 20),
    TestItem('Apple Green', 'تفاح أخضر', 'سێوی سەوز', 2, 'Kilogram', 2700, 3750, 55, weighed: true, shelfDays: 30, reorder: 15),
    TestItem('Orange', 'برتقال', 'پرتەقاڵ', 2, 'Kilogram', 1800, 2500, 90, weighed: true, shelfDays: 21, reorder: 25),
    TestItem('Lemon', 'ليمون', 'لیمۆ', 2, 'Kilogram', 2000, 3000, 40, weighed: true, shelfDays: 21, reorder: 12),
    TestItem('Grapes', 'عنب', 'ترێ', 2, 'Kilogram', 3000, 4500, 45, weighed: true, shelfDays: 10, reorder: 12),
    TestItem('Watermelon', 'رقي', 'شووتی', 2, 'Kilogram', 700, 1000, 200, weighed: true, shelfDays: 14, reorder: 50),
    TestItem('Pomegranate', 'رمان', 'هەنار', 2, 'Kilogram', 2800, 4000, 50, weighed: true, shelfDays: 30, reorder: 15),
    TestItem('Dates Zahdi', 'تمر زهدي', 'خورمای زەهدی', 2, 'Kilogram', 3000, 4500, 35, weighed: true, shelfDays: 180, reorder: 10),
    TestItem('Cantaloupe', 'بطيخ أصفر', 'کاڵەک', 2, 'Kilogram', 1200, 1750, 60, weighed: true, shelfDays: 14, reorder: 20),
    TestItem('Whole Chicken Fresh', 'دجاج كامل طازج', 'مریشکی تەواوی تازە', 3, 'Kilogram', 6000, 8000, 60, weighed: true, shelfDays: 4, reorder: 15),
    TestItem('Chicken Breast', 'صدور دجاج', 'سنگی مریشک', 3, 'Kilogram', 9000, 12000, 40, weighed: true, shelfDays: 4, reorder: 10),
    TestItem('Chicken Thigh', 'أفخاذ دجاج', 'ڕانی مریشک', 3, 'Kilogram', 7000, 9500, 35, weighed: true, shelfDays: 4, reorder: 10),
    TestItem('Chicken Wings 1kg', 'أجنحة دجاج ١كغ', 'باڵی مریشک ١کگ', 3, 'Piece', 6500, 9000, 25, shelfDays: 180, reorder: 8),
    TestItem('Beef Mince', 'لحم بقر مفروم', 'گۆشتی مانگای هاڕاو', 3, 'Kilogram', 14000, 18500, 30, weighed: true, shelfDays: 3, reorder: 8),
    TestItem('Beef Cubes', 'لحم بقر مكعبات', 'گۆشتی مانگا پارچە', 3, 'Kilogram', 15000, 20000, 25, weighed: true, shelfDays: 3, reorder: 8),
    TestItem('Lamb Chops', 'ريش غنم', 'پەراسووی مەڕ', 3, 'Kilogram', 22000, 28000, 20, weighed: true, shelfDays: 3, reorder: 5),
    TestItem('Lamb Mince', 'لحم غنم مفروم', 'گۆشتی مەڕی هاڕاو', 3, 'Kilogram', 20000, 26000, 18, weighed: true, shelfDays: 3, reorder: 5),
    TestItem('Beef Burger 10pcs', 'برجر لحم ١٠ حبات', 'بەرگەری گۆشت ١٠ دانە', 3, 'Piece', 7000, 9500, 30, shelfDays: 180, reorder: 10),
    TestItem('Chicken Burger 10pcs', 'برجر دجاج ١٠ حبات', 'بەرگەری مریشک ١٠ دانە', 3, 'Piece', 5500, 7500, 30, shelfDays: 180, reorder: 10),
    TestItem('Beef Sausage 400g', 'سجق بقري ٤٠٠غم', 'سوجوقی مانگا ٤٠٠گ', 3, 'Piece', 4500, 6000, 35, pack: 12, shelfDays: 90, reorder: 10),
    TestItem('Mortadella 250g', 'مرتديلا ٢٥٠غم', 'مۆرتەدێلای ٢٥٠گ', 3, 'Piece', 2500, 3500, 40, pack: 20, shelfDays: 90, reorder: 12),
    TestItem('Fresh Fish Carp', 'سمك كارب طازج', 'ماسی کەپوور', 3, 'Kilogram', 8000, 11000, 25, weighed: true, shelfDays: 3, reorder: 6),
    TestItem('Frozen Shrimp 500g', 'روبيان مجمد ٥٠٠غم', 'میگۆی قەتیس ٥٠٠گ', 3, 'Piece', 11000, 15000, 15, shelfDays: 365, reorder: 5),
    TestItem('Frozen Peas 400g', 'بازلاء مجمدة ٤٠٠غم', 'نۆکی قەتیس ٤٠٠گ', 4, 'Piece', 1800, 2500, 45, pack: 20, shelfDays: 365, reorder: 12),
    TestItem('Frozen Mixed Veg 400g', 'خضار مشكل مجمد ٤٠٠غم', 'سەوزەی تێکەڵ ٤٠٠گ', 4, 'Piece', 1900, 2600, 40, pack: 20, shelfDays: 365, reorder: 12),
    TestItem('Frozen Corn 400g', 'ذرة مجمدة ٤٠٠غم', 'گەنمەشامی قەتیس ٤٠٠گ', 4, 'Piece', 1700, 2400, 35, pack: 20, shelfDays: 365, reorder: 10),
    TestItem('Frozen Fries 1kg', 'بطاطا مقلية مجمدة ١كغ', 'پەتاتەی سوورکراوە ١کگ', 4, 'Piece', 3200, 4500, 50, pack: 10, shelfDays: 365, reorder: 15),
    TestItem('Frozen Pizza Margherita', 'بيتزا مجمدة مارغريتا', 'پیتزای قەتیس مارگەریتا', 4, 'Piece', 4500, 6500, 25, pack: 8, shelfDays: 270, reorder: 8),
    TestItem('Frozen Samosa 20pcs', 'سمبوسة مجمدة ٢٠ حبة', 'سەمبووسەی قەتیس ٢٠ دانە', 4, 'Piece', 3500, 5000, 30, pack: 12, shelfDays: 270, reorder: 10),
    TestItem('Vanilla Ice Cream 1L', 'آيس كريم فانيلا ١ لتر', 'بەستەنی ڤانیلا ١ لیتر', 4, 'Piece', 4000, 5750, 35, pack: 6, shelfDays: 365, reorder: 10),
    TestItem('Chocolate Ice Cream 1L', 'آيس كريم شوكولاتة ١ لتر', 'بەستەنی شۆکولات ١ لیتر', 4, 'Piece', 4200, 6000, 30, pack: 6, shelfDays: 365, reorder: 10),
    TestItem('Ice Cream Cone 6pcs', 'كون آيس كريم ٦ حبات', 'کۆنی بەستەنی ٦ دانە', 4, 'Piece', 3000, 4250, 40, pack: 8, shelfDays: 365, reorder: 12),
    TestItem('Frozen Puff Pastry 400g', 'عجينة باف ٤٠٠غم', 'هەویری پەف ٤٠٠گ', 4, 'Piece', 2500, 3500, 25, pack: 12, shelfDays: 270, reorder: 8),
    TestItem('Frozen Kubba 500g', 'كبة مجمدة ٥٠٠غم', 'کوببەی قەتیس ٥٠٠گ', 4, 'Piece', 5000, 7000, 25, pack: 10, shelfDays: 180, reorder: 8),
    TestItem('Ice Cubes 2kg', 'ثلج ٢ كغ', 'سەهۆڵی ٢ کگ', 4, 'Piece', 500, 1000, 40, shelfDays: 365, reorder: 15),
    TestItem('Cola 330ml Can', 'كولا ٣٣٠مل علبة', 'کۆلای ٣٣٠مل قوتوو', 5, 'Piece', 600, 900, 240, pack: 24, shelfDays: 270, reorder: 60),
    TestItem('Cola 1.25L', 'كولا ١.٢٥ لتر', 'کۆلای ١.٢٥ لیتر', 5, 'Piece', 1300, 1750, 120, pack: 12, shelfDays: 270, reorder: 30),
    TestItem('Cola 2.25L', 'كولا ٢.٢٥ لتر', 'کۆلای ٢.٢٥ لیتر', 5, 'Piece', 2000, 2750, 90, pack: 8, shelfDays: 270, reorder: 24),
    TestItem('Orange Soda 330ml', 'مشروب برتقال ٣٣٠مل', 'خواردنەوەی پرتەقاڵ ٣٣٠مل', 5, 'Piece', 600, 900, 180, pack: 24, shelfDays: 270, reorder: 48),
    TestItem('Lemon Soda 330ml', 'مشروب ليمون ٣٣٠مل', 'خواردنەوەی لیمۆ ٣٣٠مل', 5, 'Piece', 600, 900, 150, pack: 24, shelfDays: 270, reorder: 48),
    TestItem('Water 500ml', 'ماء ٥٠٠مل', 'ئاوی ٥٠٠مل', 5, 'Piece', 200, 400, 400, pack: 24, shelfDays: 365, reorder: 96),
    TestItem('Water 1.5L', 'ماء ١.٥ لتر', 'ئاوی ١.٥ لیتر', 5, 'Piece', 400, 700, 300, pack: 12, shelfDays: 365, reorder: 60),
    TestItem('Water 10L Gallon', 'ماء ١٠ لتر', 'ئاوی ١٠ لیتر', 5, 'Piece', 1500, 2500, 60, shelfDays: 365, reorder: 15),
    TestItem('Orange Juice 1L', 'عصير برتقال ١ لتر', 'شەربەتی پرتەقاڵ ١ لیتر', 5, 'Piece', 1800, 2500, 80, pack: 12, shelfDays: 300, reorder: 20),
    TestItem('Apple Juice 1L', 'عصير تفاح ١ لتر', 'شەربەتی سێو ١ لیتر', 5, 'Piece', 1800, 2500, 70, pack: 12, shelfDays: 300, reorder: 20),
    TestItem('Mango Nectar 250ml', 'عصير مانجو ٢٥٠مل', 'شەربەتی مانگۆ ٢٥٠مل', 5, 'Piece', 500, 800, 160, pack: 24, shelfDays: 300, reorder: 40),
    TestItem('Energy Drink 250ml', 'مشروب طاقة ٢٥٠مل', 'خواردنەوەی وزە ٢٥٠مل', 5, 'Piece', 1500, 2250, 90, pack: 24, shelfDays: 365, reorder: 24),
    TestItem('Iced Tea Peach 500ml', 'شاي مثلج خوخ ٥٠٠مل', 'چایی سارد خۆخ ٥٠٠مل', 5, 'Piece', 750, 1200, 100, pack: 12, shelfDays: 300, reorder: 24),
    TestItem('Black Tea 400g', 'شاي أسود ٤٠٠غم', 'چایی ڕەش ٤٠٠گ', 5, 'Piece', 4500, 6000, 60, pack: 12, shelfDays: 540, reorder: 15),
    TestItem('Green Tea 100 bags', 'شاي أخضر ١٠٠ كيس', 'چایی سەوز ١٠٠ کیسە', 5, 'Piece', 3500, 5000, 40, pack: 12, shelfDays: 540, reorder: 10),
    TestItem('Instant Coffee 200g', 'قهوة سريعة ٢٠٠غم', 'قاوەی خێرا ٢٠٠گ', 5, 'Piece', 7000, 9500, 35, pack: 12, shelfDays: 540, reorder: 10),
    TestItem('Turkish Coffee 250g', 'قهوة تركية ٢٥٠غم', 'قاوەی تورکی ٢٥٠گ', 5, 'Piece', 4000, 5500, 40, pack: 12, shelfDays: 365, reorder: 12),
    TestItem('Milk Powder 900g', 'حليب بودرة ٩٠٠غم', 'شیری وشک ٩٠٠گ', 5, 'Piece', 11000, 14500, 30, pack: 12, shelfDays: 540, reorder: 8),
    TestItem('Potato Chips Salt 45g', 'شبس ملح ٤٥غم', 'چپسی خوێ ٤٥گ', 6, 'Piece', 400, 650, 200, pack: 50, shelfDays: 180, reorder: 50),
    TestItem('Potato Chips Cheese 45g', 'شبس جبنة ٤٥غم', 'چپسی پەنیر ٤٥گ', 6, 'Piece', 400, 650, 180, pack: 50, shelfDays: 180, reorder: 50),
    TestItem('Corn Snack 30g', 'سناك ذرة ٣٠غم', 'خنجیلانەی گەنمەشامی ٣٠گ', 6, 'Piece', 300, 500, 220, pack: 60, shelfDays: 180, reorder: 60),
    TestItem('Salted Peanuts 200g', 'فستق مملح ٢٠٠غم', 'بستەی خوێدار ٢٠٠گ', 6, 'Piece', 1600, 2250, 60, pack: 20, shelfDays: 270, reorder: 15),
    TestItem('Mixed Nuts 250g', 'مكسرات مشكلة ٢٥٠غم', 'گوێزی تێکەڵ ٢٥٠گ', 6, 'Piece', 5000, 7000, 35, pack: 12, shelfDays: 270, reorder: 10),
    TestItem('Sunflower Seeds 200g', 'بذور دوار الشمس ٢٠٠غم', 'تۆوی گوڵەبەڕۆژە ٢٠٠گ', 6, 'Piece', 1200, 1750, 70, pack: 24, shelfDays: 270, reorder: 18),
    TestItem('Pistachio', 'فستق حلبي', 'فستقی حەلەبی', 6, 'Kilogram', 28000, 36000, 12, weighed: true, shelfDays: 270, reorder: 3),
    TestItem('Milk Chocolate 90g', 'شوكولاتة بالحليب ٩٠غم', 'شۆکولاتی شیر ٩٠گ', 6, 'Piece', 1200, 1750, 100, pack: 24, shelfDays: 365, reorder: 24),
    TestItem('Dark Chocolate 100g', 'شوكولاتة داكنة ١٠٠غم', 'شۆکولاتی تاریک ١٠٠گ', 6, 'Piece', 1500, 2250, 70, pack: 24, shelfDays: 365, reorder: 18),
    TestItem('Wafer Bar 40g', 'ويفر ٤٠غم', 'وەیفەری ٤٠گ', 6, 'Piece', 350, 600, 200, pack: 48, shelfDays: 270, reorder: 48),
    TestItem('Biscuit Cream 150g', 'بسكويت بالكريمة ١٥٠غم', 'بسکوێتی کرێم ١٥٠گ', 6, 'Piece', 800, 1250, 120, pack: 24, shelfDays: 270, reorder: 30),
    TestItem('Digestive Biscuit 250g', 'بسكويت هضم ٢٥٠غم', 'بسکوێتی هەرس ٢٥٠گ', 6, 'Piece', 1500, 2100, 60, pack: 24, shelfDays: 270, reorder: 15),
    TestItem('Chewing Gum 10pcs', 'علكة ١٠ حبات', 'بنێشتی ١٠ دانە', 6, 'Piece', 400, 750, 150, pack: 40, shelfDays: 540, reorder: 40),
    TestItem('Lollipop', 'مصاصة', 'شەکرەمەکە', 6, 'Piece', 150, 250, 300, pack: 100, shelfDays: 540, reorder: 80),
    TestItem('Halawa 400g', 'حلاوة طحينية ٤٠٠غم', 'حەلەوای ٤٠٠گ', 6, 'Piece', 2500, 3500, 40, pack: 12, shelfDays: 365, reorder: 10),
    TestItem('Honey 500g', 'عسل ٥٠٠غم', 'هەنگوینی ٥٠٠گ', 6, 'Piece', 9000, 12500, 25, pack: 12, shelfDays: 730, reorder: 6),
    TestItem('Popcorn Microwave 100g', 'فشار مايكرويف ١٠٠غم', 'پۆپکۆرنی مایکرۆ ١٠٠گ', 6, 'Piece', 600, 1000, 80, pack: 24, shelfDays: 270, reorder: 20),
    TestItem('Jelly Candy 200g', 'حلوى جيلي ٢٠٠غم', 'شیرینی جێلی ٢٠٠گ', 6, 'Piece', 900, 1400, 70, pack: 24, shelfDays: 365, reorder: 18),
    TestItem('Basmati Rice 5kg', 'رز بسمتي ٥ كغ', 'برنجی بەسمەتی ٥ کگ', 7, 'Piece', 16000, 21000, 50, pack: 5, shelfDays: 730, reorder: 12),
    TestItem('Basmati Rice 1kg', 'رز بسمتي ١ كغ', 'برنجی بەسمەتی ١ کگ', 7, 'Piece', 3400, 4500, 80, pack: 20, shelfDays: 730, reorder: 20),
    TestItem('Amber Rice 5kg', 'رز عنبر ٥ كغ', 'برنجی عەنبەر ٥ کگ', 7, 'Piece', 22000, 28000, 30, pack: 5, shelfDays: 730, reorder: 8),
    TestItem('Bulgur 1kg', 'برغل ١ كغ', 'سەوارە ١ کگ', 7, 'Piece', 2200, 3000, 60, pack: 10, shelfDays: 540, reorder: 15),
    TestItem('Wheat Flour 5kg', 'طحين ٥ كغ', 'ئاردی ٥ کگ', 7, 'Piece', 6500, 8500, 60, pack: 5, shelfDays: 365, reorder: 15),
    TestItem('Wheat Flour 1kg', 'طحين ١ كغ', 'ئاردی ١ کگ', 7, 'Piece', 1400, 2000, 80, pack: 20, shelfDays: 365, reorder: 20),
    TestItem('Spaghetti 400g', 'سباغيتي ٤٠٠غم', 'سپاگێتی ٤٠٠گ', 7, 'Piece', 900, 1400, 120, pack: 24, shelfDays: 730, reorder: 30),
    TestItem('Penne Pasta 400g', 'معكرونة بيني ٤٠٠غم', 'مەکەرۆنی پێنی ٤٠٠گ', 7, 'Piece', 950, 1450, 90, pack: 24, shelfDays: 730, reorder: 24),
    TestItem('Macaroni Elbow 400g', 'معكرونة كوع ٤٠٠غم', 'مەکەرۆنی ئانیشک ٤٠٠گ', 7, 'Piece', 900, 1400, 90, pack: 24, shelfDays: 730, reorder: 24),
    TestItem('Noodles Instant 70g', 'نودلز سريعة ٧٠غم', 'نوودڵی خێرا ٧٠گ', 7, 'Piece', 400, 700, 200, pack: 30, shelfDays: 365, reorder: 50),
    TestItem('Vermicelli 400g', 'شعيرية ٤٠٠غم', 'شەعریەی ٤٠٠گ', 7, 'Piece', 800, 1250, 60, pack: 24, shelfDays: 540, reorder: 15),
    TestItem('Red Lentils 1kg', 'عدس أحمر ١ كغ', 'نیسکی سوور ١ کگ', 7, 'Piece', 2400, 3250, 55, pack: 20, shelfDays: 540, reorder: 15),
    TestItem('Chickpeas 1kg', 'حمص ١ كغ', 'نۆکی ١ کگ', 7, 'Piece', 2600, 3500, 50, pack: 20, shelfDays: 540, reorder: 12),
    TestItem('White Beans 1kg', 'فاصوليا بيضاء ١ كغ', 'لۆبیای سپی ١ کگ', 7, 'Piece', 2800, 3750, 40, pack: 20, shelfDays: 540, reorder: 10),
    TestItem('Sugar 1kg', 'سكر ١ كغ', 'شەکری ١ کگ', 7, 'Piece', 1500, 2000, 150, pack: 25, shelfDays: 730, reorder: 40),
    TestItem('Sugar 5kg', 'سكر ٥ كغ', 'شەکری ٥ کگ', 7, 'Piece', 7000, 9000, 45, pack: 5, shelfDays: 730, reorder: 12),
    TestItem('Table Salt 1kg', 'ملح طعام ١ كغ', 'خوێی خواردن ١ کگ', 7, 'Piece', 500, 900, 90, pack: 20, shelfDays: 1095, reorder: 24),
    TestItem('Semolina 1kg', 'سميد ١ كغ', 'سەمیدی ١ کگ', 7, 'Piece', 1400, 2000, 40, pack: 20, shelfDays: 540, reorder: 10),
    TestItem('Corn Starch 400g', 'نشا ذرة ٤٠٠غم', 'نەشای گەنمەشامی ٤٠٠گ', 7, 'Piece', 1200, 1750, 35, pack: 24, shelfDays: 730, reorder: 10),
    TestItem('Oats 500g', 'شوفان ٥٠٠غم', 'جۆی ٥٠٠گ', 7, 'Piece', 2200, 3000, 40, pack: 12, shelfDays: 365, reorder: 10),
    TestItem('Sunflower Oil 1.8L', 'زيت دوار الشمس ١.٨ لتر', 'ڕۆنی گوڵەبەڕۆژە ١.٨ لیتر', 8, 'Piece', 5500, 7250, 80, pack: 6, shelfDays: 540, reorder: 20),
    TestItem('Sunflower Oil 5L', 'زيت دوار الشمس ٥ لتر', 'ڕۆنی گوڵەبەڕۆژە ٥ لیتر', 8, 'Piece', 14000, 18000, 40, pack: 4, shelfDays: 540, reorder: 10),
    TestItem('Olive Oil 500ml', 'زيت زيتون ٥٠٠مل', 'زەیتی زەیتوون ٥٠٠مل', 8, 'Piece', 9000, 12500, 30, pack: 12, shelfDays: 730, reorder: 8),
    TestItem('Corn Oil 1.8L', 'زيت ذرة ١.٨ لتر', 'ڕۆنی گەنمەشامی ١.٨ لیتر', 8, 'Piece', 5800, 7500, 45, pack: 6, shelfDays: 540, reorder: 12),
    TestItem('Ghee 900g', 'سمن ٩٠٠غم', 'ڕۆنی سادە ٩٠٠گ', 8, 'Piece', 8000, 10500, 35, pack: 12, shelfDays: 540, reorder: 10),
    TestItem('Tuna in Oil 160g', 'تونة بالزيت ١٦٠غم', 'تووناکەی ڕۆن ١٦٠گ', 8, 'Piece', 1800, 2500, 100, pack: 48, shelfDays: 1095, reorder: 24),
    TestItem('Tuna in Water 160g', 'تونة بالماء ١٦٠غم', 'تووناکەی ئاو ١٦٠گ', 8, 'Piece', 1800, 2500, 70, pack: 48, shelfDays: 1095, reorder: 18),
    TestItem('Canned Beans 400g', 'فاصوليا معلبة ٤٠٠غم', 'لۆبیای قوتوو ٤٠٠گ', 8, 'Piece', 1100, 1650, 80, pack: 24, shelfDays: 1095, reorder: 20),
    TestItem('Canned Corn 340g', 'ذرة حلوة معلبة ٣٤٠غم', 'گەنمەشامی قوتوو ٣٤٠گ', 8, 'Piece', 1300, 1900, 60, pack: 24, shelfDays: 1095, reorder: 15),
    TestItem('Canned Peas 400g', 'بازلاء معلبة ٤٠٠غم', 'نۆکی قوتوو ٤٠٠گ', 8, 'Piece', 1200, 1750, 55, pack: 24, shelfDays: 1095, reorder: 15),
    TestItem('Canned Mushroom 400g', 'فطر معلب ٤٠٠غم', 'کەڕووی قوتوو ٤٠٠گ', 8, 'Piece', 1900, 2600, 40, pack: 24, shelfDays: 1095, reorder: 10),
    TestItem('Tomato Paste 400g', 'معجون طماطة ٤٠٠غم', 'دۆشاوی تەماتەی ٤٠٠گ', 8, 'Piece', 1400, 2000, 120, pack: 24, shelfDays: 730, reorder: 30),
    TestItem('Tomato Paste 800g', 'معجون طماطة ٨٠٠غم', 'دۆشاوی تەماتەی ٨٠٠گ', 8, 'Piece', 2500, 3400, 70, pack: 12, shelfDays: 730, reorder: 18),
    TestItem('Luncheon Meat 340g', 'لانشون ٣٤٠غم', 'لەنشۆنی ٣٤٠گ', 8, 'Piece', 2600, 3500, 50, pack: 24, shelfDays: 1095, reorder: 12),
    TestItem('Sardines 125g', 'سردين ١٢٥غم', 'سەردینی ١٢٥گ', 8, 'Piece', 1300, 1900, 60, pack: 50, shelfDays: 1095, reorder: 15),
    TestItem('Coconut Milk 400ml', 'حليب جوز الهند ٤٠٠مل', 'شیری جۆزی هندی ٤٠٠مل', 8, 'Piece', 1900, 2700, 30, pack: 24, shelfDays: 730, reorder: 8),
    TestItem('Black Pepper 100g', 'فلفل أسود ١٠٠غم', 'بیبەری ڕەش ١٠٠گ', 9, 'Piece', 1800, 2500, 40, pack: 24, shelfDays: 730, reorder: 10),
    TestItem('Cumin 100g', 'كمون ١٠٠غم', 'کەمونی ١٠٠گ', 9, 'Piece', 1200, 1750, 40, pack: 24, shelfDays: 730, reorder: 10),
    TestItem('Turmeric 100g', 'كركم ١٠٠غم', 'زەردەچەوەی ١٠٠گ', 9, 'Piece', 1000, 1500, 35, pack: 24, shelfDays: 730, reorder: 10),
    TestItem('Curry Powder 100g', 'كاري ١٠٠غم', 'کەری ١٠٠گ', 9, 'Piece', 1300, 1900, 30, pack: 24, shelfDays: 730, reorder: 8),
    TestItem('Mixed Spice 200g', 'بهارات مشكلة ٢٠٠غم', 'بەهاراتی تێکەڵ ٢٠٠گ', 9, 'Piece', 2000, 2900, 45, pack: 24, shelfDays: 730, reorder: 12),
    TestItem('Sumac 200g', 'سماق ٢٠٠غم', 'سماقی ٢٠٠گ', 9, 'Piece', 1700, 2400, 30, pack: 24, shelfDays: 730, reorder: 8),
    TestItem('Dried Mint 50g', 'نعناع مجفف ٥٠غم', 'پونگی وشک ٥٠گ', 9, 'Piece', 800, 1250, 35, pack: 24, shelfDays: 540, reorder: 10),
    TestItem('Tomato Ketchup 500g', 'كاتشب ٥٠٠غم', 'کەتشەپی ٥٠٠گ', 9, 'Piece', 2000, 2900, 60, pack: 12, shelfDays: 540, reorder: 15),
    TestItem('Mayonnaise 500g', 'مايونيز ٥٠٠غم', 'مایۆنێزی ٥٠٠گ', 9, 'Piece', 2400, 3400, 50, pack: 12, shelfDays: 365, reorder: 12),
    TestItem('Chili Sauce 350g', 'صلصة حارة ٣٥٠غم', 'سۆسی تیژ ٣٥٠گ', 9, 'Piece', 1800, 2600, 40, pack: 12, shelfDays: 540, reorder: 10),
    TestItem('Vinegar 1L', 'خل ١ لتر', 'سرکەی ١ لیتر', 9, 'Piece', 1000, 1500, 45, pack: 12, shelfDays: 730, reorder: 12),
    TestItem('Soy Sauce 250ml', 'صلصة صويا ٢٥٠مل', 'سۆسی سۆیا ٢٥٠مل', 9, 'Piece', 1900, 2700, 25, pack: 24, shelfDays: 730, reorder: 8),
    TestItem('Tahini 400g', 'طحينة ٤٠٠غم', 'تەحینەی ٤٠٠گ', 9, 'Piece', 3200, 4400, 30, pack: 12, shelfDays: 365, reorder: 8),
    TestItem('Date Syrup 800g', 'دبس تمر ٨٠٠غم', 'دۆشاوی خورمای ٨٠٠گ', 9, 'Piece', 3000, 4200, 25, pack: 12, shelfDays: 540, reorder: 6),
    TestItem('Yeast 100g', 'خميرة ١٠٠غم', 'هەویرترشی ١٠٠گ', 9, 'Piece', 900, 1400, 40, pack: 24, shelfDays: 540, reorder: 12),
    TestItem('Dish Soap 750ml', 'سائل غسيل صحون ٧٥٠مل', 'سابوونی قاپشۆر ٧٥٠مل', 10, 'Piece', 1800, 2600, 70, pack: 12, shelfDays: 1095, reorder: 18),
    TestItem('Laundry Powder 3kg', 'مسحوق غسيل ٣ كغ', 'تۆزی جلشۆر ٣ کگ', 10, 'Piece', 9000, 12000, 40, pack: 4, shelfDays: 1095, reorder: 10),
    TestItem('Laundry Liquid 2L', 'سائل غسيل ٢ لتر', 'شلەی جلشۆر ٢ لیتر', 10, 'Piece', 7000, 9500, 35, pack: 6, shelfDays: 1095, reorder: 10),
    TestItem('Fabric Softener 1L', 'منعم أقمشة ١ لتر', 'نەرمکەری جل ١ لیتر', 10, 'Piece', 3000, 4200, 40, pack: 12, shelfDays: 1095, reorder: 12),
    TestItem('Bleach 1L', 'مبيض ١ لتر', 'سپیکەری ١ لیتر', 10, 'Piece', 1200, 1800, 60, pack: 12, shelfDays: 730, reorder: 15),
    TestItem('Floor Cleaner 1L', 'منظف أرضيات ١ لتر', 'پاککەری زەوی ١ لیتر', 10, 'Piece', 2000, 2900, 50, pack: 12, shelfDays: 1095, reorder: 12),
    TestItem('Glass Cleaner 500ml', 'منظف زجاج ٥٠٠مل', 'پاککەری شووشە ٥٠٠مل', 10, 'Piece', 1700, 2500, 35, pack: 12, shelfDays: 1095, reorder: 10),
    TestItem('Toilet Cleaner 750ml', 'منظف حمامات ٧٥٠مل', 'پاککەری تەوالێت ٧٥٠مل', 10, 'Piece', 1900, 2750, 40, pack: 12, shelfDays: 1095, reorder: 10),
    TestItem('Air Freshener 300ml', 'معطر جو ٣٠٠مل', 'بۆنخۆشکەری ٣٠٠مل', 10, 'Piece', 2200, 3200, 35, pack: 12, shelfDays: 1095, reorder: 10),
    TestItem('Sponge Scourer 3pcs', 'اسفنج جلي ٣ حبات', 'ئیسفەنجی ٣ دانە', 10, 'Piece', 600, 1000, 80, pack: 48, shelfDays: 1825, reorder: 20),
    TestItem('Garbage Bags 30pcs', 'أكياس قمامة ٣٠ كيس', 'کیسەی زبڵ ٣٠ دانە', 10, 'Piece', 1500, 2250, 60, pack: 24, shelfDays: 1825, reorder: 15),
    TestItem('Rubber Gloves', 'قفازات مطاطية', 'دەستکێشی لاستیکی', 10, 'Piece', 1200, 1900, 45, pack: 24, shelfDays: 1825, reorder: 12),
    TestItem('Insect Spray 400ml', 'مبيد حشرات ٤٠٠مل', 'دژە مێشوولەی ٤٠٠مل', 10, 'Piece', 3000, 4200, 30, pack: 12, shelfDays: 1095, reorder: 8),
    TestItem('Shampoo 400ml', 'شامبو ٤٠٠مل', 'شامپۆی ٤٠٠مل', 11, 'Piece', 4000, 5500, 50, pack: 12, shelfDays: 1095, reorder: 12),
    TestItem('Conditioner 400ml', 'بلسم ٤٠٠مل', 'نەرمکەری قژ ٤٠٠مل', 11, 'Piece', 4200, 5800, 35, pack: 12, shelfDays: 1095, reorder: 10),
    TestItem('Bar Soap 125g', 'صابون ١٢٥غم', 'سابوونی ١٢٥گ', 11, 'Piece', 600, 1000, 120, pack: 48, shelfDays: 1825, reorder: 30),
    TestItem('Shower Gel 500ml', 'جل استحمام ٥٠٠مل', 'جێلی خۆشۆردن ٥٠٠مل', 11, 'Piece', 3500, 4900, 40, pack: 12, shelfDays: 1095, reorder: 10),
    TestItem('Toothpaste 100ml', 'معجون أسنان ١٠٠مل', 'خەمیرەی ددان ١٠٠مل', 11, 'Piece', 1800, 2600, 80, pack: 24, shelfDays: 1095, reorder: 20),
    TestItem('Toothbrush', 'فرشاة أسنان', 'فڵچەی ددان', 11, 'Piece', 900, 1500, 70, pack: 24, shelfDays: 1825, reorder: 18),
    TestItem('Deodorant 150ml', 'مزيل عرق ١٥٠مل', 'دژە ئارەقەی ١٥٠مل', 11, 'Piece', 2800, 4000, 45, pack: 12, shelfDays: 1095, reorder: 12),
    TestItem('Hand Cream 75ml', 'كريم يدين ٧٥مل', 'کرێمی دەست ٧٥مل', 11, 'Piece', 1800, 2600, 30, pack: 24, shelfDays: 1095, reorder: 8),
    TestItem('Shaving Foam 200ml', 'رغوة حلاقة ٢٠٠مل', 'کەفی تاشین ٢٠٠مل', 11, 'Piece', 3000, 4200, 25, pack: 12, shelfDays: 1095, reorder: 6),
    TestItem('Razor 5pcs', 'شفرات حلاقة ٥ حبات', 'تیغی تاشین ٥ دانە', 11, 'Piece', 1500, 2400, 40, pack: 24, shelfDays: 1825, reorder: 10),
    TestItem('Facial Tissue 200', 'مناديل وجه ٢٠٠', 'دەستەسڕی ٢٠٠', 11, 'Piece', 1200, 1800, 90, pack: 24, shelfDays: 1825, reorder: 24),
    TestItem('Toilet Paper 8 rolls', 'ورق تواليت ٨ لفات', 'کاغەزی تەوالێت ٨ لوول', 11, 'Piece', 3500, 4900, 50, pack: 8, shelfDays: 1825, reorder: 12),
    TestItem('Sanitary Pads 10pcs', 'فوط صحية ١٠ حبات', 'پەڕۆی تەندروستی ١٠ دانە', 11, 'Piece', 2200, 3200, 45, pack: 24, shelfDays: 1825, reorder: 12),
    TestItem('Hand Sanitizer 250ml', 'معقم يدين ٢٥٠مل', 'دەرمانی دەست ٢٥٠مل', 11, 'Piece', 1500, 2300, 35, pack: 24, shelfDays: 1095, reorder: 10),
    TestItem('Baby Diapers M 40pcs', 'حفاضات أطفال M ٤٠', 'پێچەی منداڵ M ٤٠', 12, 'Piece', 11000, 14500, 30, pack: 4, shelfDays: 1825, reorder: 8),
    TestItem('Baby Diapers L 36pcs', 'حفاضات أطفال L ٣٦', 'پێچەی منداڵ L ٣٦', 12, 'Piece', 11500, 15000, 25, pack: 4, shelfDays: 1825, reorder: 8),
    TestItem('Baby Wipes 72pcs', 'مناديل مبللة ٧٢', 'دەستەسڕی تەڕ ٧٢', 12, 'Piece', 2200, 3200, 50, pack: 12, shelfDays: 1095, reorder: 12),
    TestItem('Infant Formula 400g', 'حليب أطفال ٤٠٠غم', 'شیری منداڵ ٤٠٠گ', 12, 'Piece', 13000, 17000, 25, pack: 12, shelfDays: 540, reorder: 6),
    TestItem('Baby Cereal 200g', 'سيريلاك ٢٠٠غم', 'سیرێلاکی ٢٠٠گ', 12, 'Piece', 4500, 6200, 30, pack: 12, shelfDays: 540, reorder: 8),
    TestItem('Baby Shampoo 200ml', 'شامبو أطفال ٢٠٠مل', 'شامپۆی منداڵ ٢٠٠مل', 12, 'Piece', 3200, 4500, 25, pack: 12, shelfDays: 1095, reorder: 6),
    TestItem('Feeding Bottle', 'رضاعة أطفال', 'شووشەی شیر', 12, 'Piece', 3500, 5000, 20, pack: 12, shelfDays: 1825, reorder: 5),
    TestItem('Baby Soother', 'لهاية أطفال', 'مەمکە', 12, 'Piece', 1500, 2500, 25, pack: 24, shelfDays: 1825, reorder: 6),
    TestItem('Aluminium Foil 10m', 'ورق ألمنيوم ١٠م', 'کاغەزی ئەلەمینیۆم ١٠م', 13, 'Piece', 2000, 2900, 40, pack: 24, shelfDays: 1825, reorder: 10),
    TestItem('Cling Film 30m', 'نايلون تغليف ٣٠م', 'نایلۆنی پێچان ٣٠م', 13, 'Piece', 1800, 2600, 35, pack: 24, shelfDays: 1825, reorder: 10),
    TestItem('Paper Cups 50pcs', 'أكواب ورقية ٥٠', 'جامی کاغەزی ٥٠', 13, 'Piece', 1500, 2300, 50, pack: 20, shelfDays: 1825, reorder: 12),
    TestItem('Paper Plates 25pcs', 'صحون ورقية ٢٥', 'قاپی کاغەزی ٢٥', 13, 'Piece', 1700, 2500, 40, pack: 20, shelfDays: 1825, reorder: 10),
    TestItem('Plastic Spoons 50pcs', 'ملاعق بلاستيك ٥٠', 'کەوچکی پلاستیک ٥٠', 13, 'Piece', 1000, 1700, 45, pack: 40, shelfDays: 1825, reorder: 12),
    TestItem('Matches 10 boxes', 'كبريت ١٠ علب', 'کبریتی ١٠ قوتوو', 13, 'Piece', 500, 900, 60, pack: 40, shelfDays: 1825, reorder: 15),
    TestItem('Candles 6pcs', 'شموع ٦ حبات', 'مۆمی ٦ دانە', 13, 'Piece', 1200, 1900, 30, pack: 24, shelfDays: 1825, reorder: 8),
    TestItem('AA Batteries 4pcs', 'بطاريات AA ٤ حبات', 'باتری AA ٤ دانە', 13, 'Piece', 2000, 3000, 40, pack: 24, shelfDays: 1825, reorder: 10),
    TestItem('LED Bulb 9W', 'لمبة ليد ٩ واط', 'گڵۆپی لێد ٩ وات', 13, 'Piece', 2500, 3800, 35, pack: 20, shelfDays: 1825, reorder: 8),
    TestItem('Broom', 'مكنسة', 'گسک', 13, 'Piece', 3000, 4500, 15, shelfDays: 1825, reorder: 4),
    TestItem('Bucket 10L', 'دلو ١٠ لتر', 'سەتڵی ١٠ لیتر', 13, 'Piece', 2500, 3900, 18, shelfDays: 1825, reorder: 5),
    TestItem('Charcoal 3kg', 'فحم ٣ كغ', 'خەڵووزی ٣ کگ', 13, 'Piece', 3500, 5000, 25, shelfDays: 1825, reorder: 6),
    TestItem('Cigarettes Pack', 'علبة سجائر', 'پاکێتی جگەرە', 14, 'Piece', 3500, 4500, 120, pack: 10, shelfDays: 540, reorder: 30),
    TestItem('Cigarettes Carton', 'كرتون سجائر', 'کارتۆنی جگەرە', 14, 'Piece', 34000, 43000, 20, shelfDays: 540, reorder: 5),
    TestItem('Lighter', 'ولاعة', 'داگیرسێنەر', 14, 'Piece', 500, 1000, 90, pack: 50, shelfDays: 1825, reorder: 25),
    TestItem('Shisha Tobacco 50g', 'معسل ٥٠غم', 'تووتنی نەرگیلە ٥٠گ', 14, 'Piece', 2500, 3800, 40, pack: 24, shelfDays: 540, reorder: 10),
    TestItem('Shisha Charcoal', 'فحم نركيلة', 'خەڵووزی نەرگیلە', 14, 'Piece', 1500, 2500, 35, pack: 20, shelfDays: 1825, reorder: 10),
  ];

  /// Loads the test catalogue.
  ///
  /// One transaction: either the shop gets the whole catalogue or it gets
  /// nothing, because half a catalogue with a matching half a journal entry is
  /// the one outcome nobody could unpick afterwards.
  static Future<TestCatalogueReport> run(
    AppDatabase database, {
    int? userId,
  }) async {
    final TestCatalogueReport report =
        await database.transaction<TestCatalogueReport>((Transaction txn) async {
      final String now = Time.stamp();
      final DateTime today = DateTime.now();

      // ------------------------------------------------------------ units --
      final Map<String, int> units = <String, int>{};
      for (final Map<String, Object?> row
          in await txn.query('units', columns: <String>['id', 'name'])) {
        units['${row['name']}'] = row['id'] as int;
      }
      // A missing unit is refused rather than quietly swapped for pieces: a
      // kilo of tomatoes filed as a piece would price the whole aisle wrong,
      // and it would look right on screen.
      int unitId(String name) {
        final int? id = units[name];
        if (id == null) {
          throw AppFailure.validation('The unit "\$name" is missing.');
        }
        return id;
      }

      // ------------------------------------------------------- categories --
      final List<int> categoryIds = <int>[];
      int newCategories = 0;
      for (int i = 0; i < categories.length; i++) {
        final List<String> c = categories[i];
        final List<Map<String, Object?>> found = await txn.query(
          'categories',
          columns: <String>['id'],
          where: 'name = ?',
          whereArgs: <Object?>[c[0]],
          limit: 1,
        );
        if (found.isNotEmpty) {
          categoryIds.add(found.first['id'] as int);
          continue;
        }
        categoryIds.add(await txn.insert('categories', <String, Object?>{
          'name': c[0],
          'name_ar': c[1],
          'name_ku': c[2],
          'color': c[3],
          'sort_order': i + 1,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        }));
        newCategories++;
      }

      // ------------------------------------------------------------ items --
      int newItems = 0;
      int newBarcodes = 0;
      int newBatches = 0;
      int stockValueMinor = 0;
      int scaleCode = 10000;

      for (int i = 0; i < items.length; i++) {
        final TestItem d = items[i];
        final String sku = 'TEST-${(i + 1).toString().padLeft(4, '0')}';

        final List<Map<String, Object?>> existing = await txn.query(
          'items',
          columns: <String>['id'],
          where: 'sku = ?',
          whereArgs: <Object?>[sku],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;

        if (d.weighed) scaleCode++;

        final int itemId = await txn.insert('items', <String, Object?>{
          'sku': sku,
          'name': d.en,
          'name_ar': d.ar,
          'name_ku': d.ku,
          'category_id': categoryIds[d.category],
          'base_unit_id': unitId(d.unit),
          'kind': 'stock',
          'track_stock': 1,
          'is_service': 0,
          'allow_negative': 0,
          'is_weighed': d.weighed ? 1 : 0,
          'scale_code': d.weighed ? '$scaleCode' : null,
          'track_batches': d.tracksBatches ? 1 : 0,
          'reorder_level_milli': d.reorder * 1000,
          'tax_rate_bp': 0,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        newItems++;

        // The base unit, priced. `min_price_minor` is set a little under the
        // shelf price so the minimum-price floor has something to enforce.
        await txn.insert('item_units', <String, Object?>{
          'item_id': itemId,
          'unit_id': unitId(d.unit),
          'factor_milli': 1000,
          'sell_price_minor': d.price * 100,
          'wholesale_price_minor': ((d.cost + d.price) ~/ 2) * 100,
          'min_price_minor': d.cost * 100,
          'barcode': _ean13('6261${(i + 1).toString().padLeft(8, '0')}'),
          'is_base': 1,
          'is_default_sale': 1,
          'is_default_purchase': d.pack == 0 ? 1 : 0,
          'sort_order': 0,
        });
        newBarcodes++;

        // A carton, where the shop buys by the carton. Its price is the base
        // price times the factor less a shade, which is what makes a wholesale
        // line in a receipt look like one.
        if (d.pack > 0) {
          await txn.insert('item_units', <String, Object?>{
            'item_id': itemId,
            'unit_id': unitId('Carton'),
            'factor_milli': d.pack * 1000,
            'sell_price_minor': d.price * d.pack * 95,
            'wholesale_price_minor': d.price * d.pack * 90,
            'min_price_minor': d.cost * d.pack * 100,
            'barcode': _ean13('6262${(i + 1).toString().padLeft(8, '0')}'),
            'is_base': 0,
            'is_default_sale': 0,
            'is_default_purchase': 1,
            'sort_order': 1,
          });
          newBarcodes++;
        }

        // -------------------------------------------------- opening stock --
        final int qtyMilli = d.qty * 1000;
        final int costMinor = d.cost * 100;

        if (d.tracksBatches) {
          // Two lots on the shelf, one older than the other, so the expiry
          // screen and FEFO picking have something real to work with.
          final int olderQty = qtyMilli ~/ 3;
          final int newerQty = qtyMilli - olderQty;

          final int older = await BatchService.upsert(
            txn,
            itemId: itemId,
            batchNo: 'L${(i + 1).toString().padLeft(4, '0')}A',
            expiryDate: Time.dayOf(
              today.add(Duration(days: d.shelfDays < 4 ? 1 : d.shelfDays ~/ 4)),
            ),
            unitCostMinor: costMinor,
            note: 'Test data',
          );
          final int newer = await BatchService.upsert(
            txn,
            itemId: itemId,
            batchNo: 'L${(i + 1).toString().padLeft(4, '0')}B',
            expiryDate: Time.dayOf(today.add(Duration(days: d.shelfDays))),
            unitCostMinor: costMinor,
            note: 'Test data',
          );
          newBatches += 2;

          for (final List<int> lot in <List<int>>[
            <int>[older, olderQty],
            <int>[newer, newerQty],
          ]) {
            if (lot[1] <= 0) continue;
            await StockService.receive(
              txn,
              itemId: itemId,
              qtyBaseMilli: lot[1],
              unitCostMinor: costMinor,
              kind: 'opening',
              docType: 'test',
              userId: userId,
              batchId: lot[0],
              note: 'Test opening stock',
            );
          }
        } else {
          await StockService.receive(
            txn,
            itemId: itemId,
            qtyBaseMilli: qtyMilli,
            unitCostMinor: costMinor,
            kind: 'opening',
            docType: 'test',
            userId: userId,
            note: 'Test opening stock',
          );
        }

        stockValueMinor += (qtyMilli * costMinor) ~/ 1000;
      }

      // ---------------------------------------------------------- posting --
      //
      // One entry for the lot rather than one per item: the shop opened with a
      // shelf full of goods, and that is a single event in its books.
      if (stockValueMinor > 0) {
        final int inventory =
            await AppDatabase.accountIdIn(txn, AccountKeys.inventory);
        final int opening =
            await AppDatabase.accountIdIn(txn, AccountKeys.openingEquity);

        await Journal.post(
          txn,
          sourceType: 'opening',
          memo: 'Test opening stock',
          userId: userId,
          lines: <JournalLine>[
            JournalLine.debit(inventory, stockValueMinor),
            JournalLine.credit(opening, stockValueMinor),
          ],
        );
      }

      await Audit.write(
        txn,
        action: Audit.settingsSave,
        entity: 'test_catalogue',
        userId: userId,
        detail: 'seeded $newItems items in $newCategories categories',
      );

      return TestCatalogueReport(
        categories: newCategories,
        items: newItems,
        barcodes: newBarcodes,
        batches: newBatches,
        stockValueMinor: stockValueMinor,
      );
    });

    if (report.items > 0) {
      await database.setSetting(settingKey, '1');
    }
    return report;
  }

  /// Turns twelve digits into a scannable EAN-13.
  ///
  /// Written out rather than pulled from a package because it is six lines and
  /// because a barcode that fails at the till is worse than no barcode: a
  /// cashier who scans a test item wants the same beep a real one gives.
  static String _ean13(String body12) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final int d = body12.codeUnitAt(i) - 48;
      sum += i.isEven ? d : d * 3;
    }
    return '$body12${(10 - (sum % 10)) % 10}';
  }
}
