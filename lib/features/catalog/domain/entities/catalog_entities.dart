import 'dart:convert';

import '../../../../core/classes/enums.dart';
import '../../../../core/money/money.dart';

/// A unit an item can be bought or sold in.
///
/// `factorMilli` is how many **base** units one of these holds, ×1000: a carton
/// of 12 pieces is `12000`. The base unit itself is always `1000`. Every price
/// belongs to a unit, so a piece and a carton can never accidentally share one —
/// and every barcode belongs to a unit too, which is what makes scanning the
/// code printed on a carton add a carton rather than a piece.
class ItemUnit {
  const ItemUnit({
    required this.id,
    required this.itemId,
    required this.unitId,
    required this.unitName,
    required this.factorMilli,
    required this.sellPrice,
    required this.wholesalePrice,
    required this.minPrice,
    required this.isBase,
    required this.isDefaultSale,
    required this.isDefaultPurchase,
    this.barcode,
    this.sortOrder = 0,
  });

  factory ItemUnit.fromMap(Map<String, Object?> m) => ItemUnit(
        id: m['id'] as int?,
        itemId: m['item_id'] as int? ?? 0,
        unitId: m['unit_id'] as int? ?? 0,
        unitName: '${m['unit_name'] ?? ''}',
        factorMilli: m['factor_milli'] as int? ?? 1000,
        sellPrice: Money.fromDb(m['sell_price_minor']),
        wholesalePrice: Money.fromDb(m['wholesale_price_minor']),
        minPrice: Money.fromDb(m['min_price_minor']),
        isBase: (m['is_base'] as int? ?? 0) == 1,
        isDefaultSale: (m['is_default_sale'] as int? ?? 0) == 1,
        isDefaultPurchase: (m['is_default_purchase'] as int? ?? 0) == 1,
        barcode: m['barcode'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  final int? id;
  final int itemId;
  final int unitId;
  final String unitName;
  final int factorMilli;
  final Money sellPrice;
  final Money wholesalePrice;
  final Money minPrice;
  final bool isBase;
  final bool isDefaultSale;
  final bool isDefaultPurchase;
  final String? barcode;
  final int sortOrder;

  double get factor => factorMilli / 1000;

  Money priceFor(PriceMode mode) =>
      mode == PriceMode.wholesale && wholesalePrice.isPositive
          ? wholesalePrice
          : sellPrice;

  Map<String, Object?> toDb(int itemId) => <String, Object?>{
        'item_id': itemId,
        'unit_id': unitId,
        'factor_milli': factorMilli,
        'sell_price_minor': sellPrice.minor,
        'wholesale_price_minor': wholesalePrice.minor,
        'min_price_minor': minPrice.minor,
        'barcode': (barcode ?? '').trim().isEmpty ? null : barcode!.trim(),
        'is_base': isBase ? 1 : 0,
        'is_default_sale': isDefaultSale ? 1 : 0,
        'is_default_purchase': isDefaultPurchase ? 1 : 0,
        'sort_order': sortOrder,
      };

  ItemUnit copyWith({
    int? id,
    int? unitId,
    String? unitName,
    int? factorMilli,
    Money? sellPrice,
    Money? wholesalePrice,
    Money? minPrice,
    bool? isBase,
    bool? isDefaultSale,
    bool? isDefaultPurchase,
    String? barcode,
    bool clearBarcode = false,
    int? sortOrder,
  }) =>
      ItemUnit(
        id: id ?? this.id,
        itemId: itemId,
        unitId: unitId ?? this.unitId,
        unitName: unitName ?? this.unitName,
        factorMilli: factorMilli ?? this.factorMilli,
        sellPrice: sellPrice ?? this.sellPrice,
        wholesalePrice: wholesalePrice ?? this.wholesalePrice,
        minPrice: minPrice ?? this.minPrice,
        isBase: isBase ?? this.isBase,
        isDefaultSale: isDefaultSale ?? this.isDefaultSale,
        isDefaultPurchase: isDefaultPurchase ?? this.isDefaultPurchase,
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// A product, a service, a bundle, or the group that holds a set of variants.
class Item {
  const Item({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUnitId,
    required this.baseUnitName,
    required this.stockQtyMilli,
    required this.avgCost,
    required this.lastCost,
    required this.trackStock,
    required this.isActive,
    this.sku,
    this.categoryId,
    this.categoryName,
    this.description,
    this.imagePath,
    this.taxRateBp = 0,
    this.reorderLevelMilli = 0,
    this.allowNegative = false,
    this.expiryDate,
    this.units = const <ItemUnit>[],
    this.defaultSellPrice = Money.zero,
    this.primaryBarcode,
    this.parentItemId,
    this.parentName,
    this.variantName,
    this.variantAttrs = const <String, String>{},
    this.variantCount = 0,
    this.variantsStockMilli = 0,
    this.componentCount = 0,
    this.bundleCost = Money.zero,
    this.isWeighed = false,
    this.trackBatches = false,
    this.scaleCode,
  });

  factory Item.fromMap(
    Map<String, Object?> m, {
    List<ItemUnit> units = const <ItemUnit>[],
    Money bundleCost = Money.zero,
  }) =>
      Item(
        id: m['id'] as int,
        name: '${m['name']}',
        kind: ItemKind.fromDb(m['kind']),
        baseUnitId: m['base_unit_id'] as int? ?? 0,
        baseUnitName: '${m['base_unit_name'] ?? ''}',
        stockQtyMilli: m['stock_qty_milli'] as int? ?? 0,
        avgCost: Money.fromDb(m['avg_cost_minor']),
        lastCost: Money.fromDb(m['last_cost_minor']),
        trackStock: (m['track_stock'] as int? ?? 1) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        sku: m['sku'] as String?,
        categoryId: m['category_id'] as int?,
        categoryName: m['category_name'] as String?,
        description: m['description'] as String?,
        imagePath: m['image_path'] as String?,
        taxRateBp: m['tax_rate_bp'] as int? ?? 0,
        reorderLevelMilli: m['reorder_level_milli'] as int? ?? 0,
        allowNegative: (m['allow_negative'] as int? ?? 0) == 1,
        expiryDate: m['expiry_date'] as String?,
        units: units,
        defaultSellPrice: Money.fromDb(m['default_sell_price_minor']),
        primaryBarcode: m['primary_barcode'] as String?,
        parentItemId: m['parent_item_id'] as int?,
        parentName: m['parent_name'] as String?,
        variantName: m['variant_name'] as String?,
        variantAttrs: decodeAttrs(m['variant_attrs']),
        variantCount: m['variant_count'] as int? ?? 0,
        variantsStockMilli: (m['variants_stock_milli'] as num?)?.toInt() ?? 0,
        componentCount: m['component_count'] as int? ?? 0,
        bundleCost: bundleCost,
        isWeighed: (m['is_weighed'] as int? ?? 0) == 1,
        trackBatches: (m['track_batches'] as int? ?? 0) == 1,
        scaleCode: m['scale_code'] as String?,
      );

  final int id;
  final String name;
  final ItemKind kind;
  final int baseUnitId;
  final String baseUnitName;
  final int stockQtyMilli;
  final Money avgCost;
  final Money lastCost;
  final bool trackStock;
  final bool isActive;
  final String? sku;
  final int? categoryId;
  final String? categoryName;
  final String? description;
  final String? imagePath;
  final int taxRateBp;
  final int reorderLevelMilli;
  final bool allowNegative;
  final String? expiryDate;
  final List<ItemUnit> units;
  final Money defaultSellPrice;
  final String? primaryBarcode;

  /// Set on a variant: the `group` item it belongs to.
  final int? parentItemId;
  final String? parentName;
  final String? variantName;
  final Map<String, String> variantAttrs;

  /// Set on a group: how many variants hang off it.
  final int variantCount;
  final int variantsStockMilli;

  /// Set on a bundle.
  final int componentCount;
  final Money bundleCost;

  final bool isWeighed;

  /// Counted by batch, with expiry dates.
  final bool trackBatches;
  final String? scaleCode;

  Qty get stock => Qty(stockQtyMilli);

  bool get isVariant => parentItemId != null;
  bool get isGroup => kind == ItemKind.group;
  bool get isBundle => kind == ItemKind.bundle;
  bool get isService => kind == ItemKind.service;

  /// What the till and the tables show. A variant is "Shirt — Red / L", which
  /// is the only label that makes sense once it is on a receipt on its own.
  String get displayName {
    final String? v = variantName;
    if (v == null || v.trim().isEmpty) return name;
    return '$name — $v';
  }

  /// A bundle's cost is its parts'; everything else costs what it costs.
  Money get effectiveCost => isBundle ? bundleCost : avgCost;

  Money get stockValue => Money((stockQtyMilli * avgCost.minor) ~/ 1000);

  bool get isLowStock =>
      trackStock &&
      kind.movesStock &&
      reorderLevelMilli > 0 &&
      stockQtyMilli <= reorderLevelMilli;

  bool get isOutOfStock =>
      trackStock && kind == ItemKind.stock && stockQtyMilli <= 0;

  ItemUnit? get saleUnit {
    if (units.isEmpty) return null;
    return units.firstWhere(
      (ItemUnit u) => u.isDefaultSale,
      orElse: () => units.firstWhere(
        (ItemUnit u) => u.isBase,
        orElse: () => units.first,
      ),
    );
  }

  ItemUnit? get purchaseUnit {
    if (units.isEmpty) return null;
    return units.firstWhere(
      (ItemUnit u) => u.isDefaultPurchase,
      orElse: () => saleUnit ?? units.first,
    );
  }

  ItemUnit? unitById(int? itemUnitId) {
    if (itemUnitId == null) return saleUnit;
    for (final ItemUnit u in units) {
      if (u.id == itemUnitId) return u;
    }
    return saleUnit;
  }

  /// Only the fields a screen ever flips on a row it already has. Anything
  /// structural — a price, a unit, a kind — goes back through the repository,
  /// because changing it in memory would put the table and the database into
  /// two different stories.
  Item copyWith({
    String? name,
    bool? isActive,
    int? stockQtyMilli,
    Money? avgCost,
    List<ItemUnit>? units,
    Money? bundleCost,
  }) =>
      Item(
        id: id,
        name: name ?? this.name,
        kind: kind,
        baseUnitId: baseUnitId,
        baseUnitName: baseUnitName,
        stockQtyMilli: stockQtyMilli ?? this.stockQtyMilli,
        avgCost: avgCost ?? this.avgCost,
        lastCost: lastCost,
        trackStock: trackStock,
        isActive: isActive ?? this.isActive,
        sku: sku,
        categoryId: categoryId,
        categoryName: categoryName,
        description: description,
        imagePath: imagePath,
        taxRateBp: taxRateBp,
        reorderLevelMilli: reorderLevelMilli,
        allowNegative: allowNegative,
        expiryDate: expiryDate,
        units: units ?? this.units,
        defaultSellPrice: defaultSellPrice,
        primaryBarcode: primaryBarcode,
        parentItemId: parentItemId,
        parentName: parentName,
        variantName: variantName,
        variantAttrs: variantAttrs,
        variantCount: variantCount,
        variantsStockMilli: variantsStockMilli,
        componentCount: componentCount,
        bundleCost: bundleCost ?? this.bundleCost,
        isWeighed: isWeighed,
        trackBatches: trackBatches,
        scaleCode: scaleCode,
      );

  static Map<String, String> decodeAttrs(Object? raw) {
    final String text = '${raw ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return const <String, String>{};
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) {
        return decoded.map(
          (Object? k, Object? v) => MapEntry<String, String>('$k', '$v'),
        );
      }
    } catch (_) {
      // A hand-edited database should not stop the till from opening.
    }
    return const <String, String>{};
  }

  static String encodeAttrs(Map<String, String> attrs) =>
      attrs.isEmpty ? '' : jsonEncode(attrs);
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.parentId,
    this.imagePath,
    this.color,
    this.itemCount = 0,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: '${m['name']}',
        parentId: m['parent_id'] as int?,
        imagePath: m['image_path'] as String?,
        color: m['color'] as String?,
        itemCount: m['item_count'] as int? ?? 0,
        sortOrder: m['sort_order'] as int? ?? 0,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  final int id;
  final String name;
  final int? parentId;
  final String? imagePath;
  final String? color;
  final int itemCount;
  final int sortOrder;
  final bool isActive;
}

class UnitDef {
  const UnitDef({
    required this.id,
    required this.name,
    this.symbol,
    this.allowFraction = false,
    this.isActive = true,
    this.usageCount = 0,
  });

  factory UnitDef.fromMap(Map<String, Object?> m) => UnitDef(
        id: m['id'] as int,
        name: '${m['name']}',
        symbol: m['symbol'] as String?,
        allowFraction: (m['allow_fraction'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        usageCount: m['usage_count'] as int? ?? 0,
      );

  final int id;
  final String name;
  final String? symbol;

  /// Kilograms and metres can be sold in halves; pieces cannot. The till uses
  /// this to decide whether the quantity keypad offers a decimal point.
  final bool allowFraction;
  final bool isActive;
  final int usageCount;

  String get label => (symbol ?? '').isEmpty ? name : '$name ($symbol)';
}

/// One thing that varies across a group's variants: `Size` → `S, M, L`.
class VariantAxis {
  const VariantAxis({
    this.id,
    required this.name,
    required this.values,
    this.sortOrder = 0,
  });

  factory VariantAxis.fromMap(Map<String, Object?> m) => VariantAxis(
        id: m['id'] as int?,
        name: '${m['name']}',
        values: '${m['values_csv'] ?? ''}'
            .split(',')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList(growable: false),
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  final int? id;
  final String name;
  final List<String> values;
  final int sortOrder;

  Map<String, Object?> toDb(int itemId) => <String, Object?>{
        'item_id': itemId,
        'name': name.trim(),
        'values_csv': values.join(', '),
        'sort_order': sortOrder,
      };

  VariantAxis copyWith({String? name, List<String>? values, int? sortOrder}) =>
      VariantAxis(
        id: id,
        name: name ?? this.name,
        values: values ?? this.values,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// One part of a bundle, as the editor holds it.
class BundlePart {
  const BundlePart({
    this.id,
    required this.componentItemId,
    required this.componentName,
    required this.qtyMilli,
    this.itemUnitId,
    this.unitName = '',
    this.factorMilli = 1000,
    this.avgCost = Money.zero,
    this.sortOrder = 0,
  });

  factory BundlePart.fromMap(Map<String, Object?> m) => BundlePart(
        id: m['id'] as int?,
        componentItemId: m['component_item_id'] as int,
        componentName: '${m['component_name'] ?? ''}',
        qtyMilli: m['qty_milli'] as int? ?? 1000,
        itemUnitId: m['item_unit_id'] as int?,
        unitName: '${m['unit_name'] ?? ''}',
        factorMilli: m['factor_milli'] as int? ?? 1000,
        avgCost: Money.fromDb(m['avg_cost_minor']),
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  final int? id;
  final int componentItemId;
  final String componentName;
  final int qtyMilli;
  final int? itemUnitId;
  final String unitName;
  final int factorMilli;
  final Money avgCost;
  final int sortOrder;

  /// What one bundle's worth of this part costs today.
  Money get lineCost =>
      Money((avgCost.minor * ((qtyMilli * factorMilli) ~/ 1000)) ~/ 1000);

  Map<String, Object?> toDb(int bundleItemId) => <String, Object?>{
        'bundle_item_id': bundleItemId,
        'component_item_id': componentItemId,
        'item_unit_id': itemUnitId,
        'qty_milli': qtyMilli,
        'sort_order': sortOrder,
      };

  BundlePart copyWith({int? qtyMilli, int? itemUnitId, String? unitName, int? factorMilli}) =>
      BundlePart(
        id: id,
        componentItemId: componentItemId,
        componentName: componentName,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        itemUnitId: itemUnitId ?? this.itemUnitId,
        unitName: unitName ?? this.unitName,
        factorMilli: factorMilli ?? this.factorMilli,
        avgCost: avgCost,
        sortOrder: sortOrder,
      );
}

/// What a scan resolved to: the product, the unit whose barcode matched, and —
/// for a scale label — the weight that was printed on it.
class BarcodeHit {
  const BarcodeHit({required this.item, required this.unit, this.qty});

  final Item item;
  final ItemUnit? unit;
  final Qty? qty;
}

/// Everything the item editor needs in one object, so opening the form is one
/// round trip rather than five.
class ItemDraft {
  const ItemDraft({
    required this.item,
    required this.units,
    required this.axes,
    required this.parts,
    required this.variants,
  });

  final Item? item;
  final List<ItemUnit> units;
  final List<VariantAxis> axes;
  final List<BundlePart> parts;

  /// The variants hanging off this group.
  final List<Item> variants;
}

/// One recorded move of one of an item's three prices.
class PriceChange {
  const PriceChange({
    required this.field,
    required this.oldPrice,
    required this.newPrice,
    required this.changedAt,
    this.unitName,
    this.userName,
  });

  factory PriceChange.fromMap(Map<String, Object?> m) => PriceChange(
        field: '${m['field']}',
        oldPrice: Money.fromDb(m['old_minor']),
        newPrice: Money.fromDb(m['new_minor']),
        changedAt: '${m['changed_at']}',
        unitName: m['unit_name'] as String?,
        userName: m['user_name'] as String?,
      );

  /// One of `sell`, `wholesale`, `min`.
  final String field;

  final Money oldPrice;
  final Money newPrice;
  final String changedAt;
  final String? unitName;
  final String? userName;

  Money get delta => Money(newPrice.minor - oldPrice.minor);

  bool get isRise => newPrice.minor > oldPrice.minor;
}

/// What the goods cost on one delivery.
class CostPoint {
  const CostPoint({
    required this.movedAt,
    required this.kind,
    required this.unitCost,
    required this.qtyMilli,
    this.partyName,
  });

  factory CostPoint.fromMap(Map<String, Object?> m) => CostPoint(
        movedAt: '${m['moved_at']}',
        kind: '${m['kind']}',
        unitCost: Money.fromDb(m['unit_cost_minor']),
        qtyMilli: m['qty_milli'] as int? ?? 0,
        partyName: m['party_name'] as String?,
      );

  final String movedAt;
  final String kind;
  final Money unitCost;
  final int qtyMilli;
  final String? partyName;
}

/// Both trails, fetched together because the screen shows them side by side.
class ItemHistory {
  const ItemHistory({
    this.prices = const <PriceChange>[],
    this.costs = const <CostPoint>[],
  });

  final List<PriceChange> prices;
  final List<CostPoint> costs;

  bool get isEmpty => prices.isEmpty && costs.isEmpty;
}
