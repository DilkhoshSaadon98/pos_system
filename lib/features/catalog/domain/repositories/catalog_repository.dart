import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/money.dart';
import '../entities/catalog_entities.dart';

/// Items, categories and units, as the screens see them.
///
/// Everything returns `Result<T>` — the value or the reason there isn't one.
/// Nothing here throws, so no screen can forget a try/catch and end up showing
/// an empty table where an error belongs.
abstract class CatalogRepository {
  Future<Result<List<Item>>> searchItems({
    String? text,
    int? categoryId,
    StockFilter filter = StockFilter.all,
    Set<ItemKind>? kinds,

    /// Variants are hidden from the item list by default — a shop with four
    /// sizes and three colours of one shirt wants to see one row, not twelve.
    bool includeVariants = false,
    int limit = 300,
    int offset = 0,
  });

  Future<Result<Item?>> itemById(int id, {bool withUnits = true});

  /// The variants hanging off a group, ready for the till's picker.
  Future<Result<List<Item>>> variantsOf(int groupItemId);

  /// Everything the editor needs for one item, in a single round trip.
  Future<Result<ItemDraft>> loadDraft(int? id);

  /// Resolves a scan. Understands three things, in this order: a unit barcode,
  /// a scale label carrying a weight or a price, and an item code typed by
  /// hand.
  Future<Result<BarcodeHit?>> resolveScan(String code);

  Future<Result<List<ItemUnit>>> unitsOfItem(int itemId);

  Future<Result<int>> saveItem(ItemSaveRequest request);

  /// Builds every missing combination of the group's axes as a real variant,
  /// copying the group's units and prices. Returns how many were created.
  Future<Result<int>> generateVariants(int groupItemId);

  Future<Result<Unit>> removeItem(int id);

  Future<Result<Unit>> setItemActive(int id, bool active);

  /// Sets an item's stock to a counted figure and posts the difference to the
  /// books, so the inventory account keeps matching the stock it represents.
  Future<Result<Unit>> adjustStock({
    required int itemId,
    required Qty counted,
    int? userId,
    String? note,
    bool isOpening = false,
  });

  /// What this item's prices and costs have done over time.
  Future<Result<ItemHistory>> history(int itemId, {int limit = 60});

  Future<Result<List<Category>>> categories({bool onlyActive = true});
  Future<Result<int>> saveCategory(CategorySaveRequest request);
  Future<Result<Unit>> removeCategory(int id);

  Future<Result<List<UnitDef>>> units({bool onlyActive = true});
  Future<Result<int>> saveUnit(UnitSaveRequest request);
  Future<Result<Unit>> removeUnit(int id);
}

/// One item, its units, its variant axes and its bundle parts, saved together.
///
/// A request object rather than eighteen named parameters, because the item
/// form fills it in over several tabs and hands the whole thing over once —
/// which is also what makes the save a single transaction.
class ItemSaveRequest {
  const ItemSaveRequest({
    this.id,
    required this.name,
    required this.kind,
    required this.baseUnitId,
    required this.units,
    this.sku,
    this.categoryId,
    this.description,
    this.imagePath,
    this.taxRateBp = 0,
    this.reorderLevelMilli = 0,
    this.trackStock = true,
    this.allowNegative = false,
    this.expiryDate,
    this.isActive = true,
    this.parentItemId,
    this.variantName,
    this.variantAttrs = const <String, String>{},
    this.axes = const <VariantAxis>[],
    this.parts = const <BundlePart>[],
    this.isWeighed = false,
    this.trackBatches = false,
    this.scaleCode,
    this.openingCost,
  });

  final int? id;
  final String name;
  final ItemKind kind;
  final int baseUnitId;
  final List<ItemUnit> units;
  final String? sku;
  final int? categoryId;
  final String? description;
  final String? imagePath;
  final int taxRateBp;
  final int reorderLevelMilli;
  final bool trackStock;
  final bool allowNegative;
  final String? expiryDate;
  final bool isActive;
  final int? parentItemId;
  final String? variantName;
  final Map<String, String> variantAttrs;
  final List<VariantAxis> axes;
  final List<BundlePart> parts;
  final bool isWeighed;

  /// Counted by batch, with an expiry date per delivery. Only meaningful for a
  /// stocked item — a service has nothing to expire.
  final bool trackBatches;
  final String? scaleCode;

  /// Only honoured on an item that has never been bought — the one moment a
  /// cost may be typed by hand. After that, cost comes from purchases.
  final Money? openingCost;
}

class CategorySaveRequest {
  const CategorySaveRequest({
    this.id,
    required this.name,
    this.parentId,
    this.imagePath,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int? id;
  final String name;
  final int? parentId;
  final String? imagePath;
  final String? color;
  final int sortOrder;
  final bool isActive;
}

class UnitSaveRequest {
  const UnitSaveRequest({
    this.id,
    required this.name,
    this.symbol,
    this.allowFraction = false,
    this.isActive = true,
  });

  final int? id;
  final String name;
  final String? symbol;
  final bool allowFraction;
  final bool isActive;
}
