import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/accounting/account_keys.dart';
import '../../../../core/accounting/journal.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/inventory/scale_barcode.dart';
import '../../../../core/inventory/stock_service.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/audit.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';

/// Every statement the catalogue runs, and nothing else.
///
/// Two rules hold throughout. **Everything is parameterised** — the old data
/// layer built SQL by pasting the contents of a text field into a string, so
/// one apostrophe in an item name broke a search. And **anything that belongs
/// together is written in one transaction**: an item and its units, a group and
/// its axes, a bundle and its parts. An item can never be left half-priced.
class CatalogLocalDataSource {
  CatalogLocalDataSource(this._database);

  final AppDatabase _database;

  // ----------------------------------------------------------------- items --

  Future<List<Item>> searchItems({
    String? text,
    int? categoryId,
    StockFilter filter = StockFilter.all,
    Set<ItemKind>? kinds,
    bool includeVariants = false,
    int limit = 300,
    int offset = 0,
  }) async {
    final StringBuffer where = StringBuffer('1 = 1');
    final List<Object?> args = <Object?>[];

    switch (filter) {
      case StockFilter.all:
        where.write(' AND is_active = 1');
      case StockFilter.hidden:
        where.write(' AND is_active = 0');
      case StockFilter.low:
        where.write(" AND is_active = 1 AND track_stock = 1 AND kind = 'stock'"
            ' AND reorder_level_milli > 0'
            ' AND stock_qty_milli <= reorder_level_milli');
      case StockFilter.out:
        where.write(" AND is_active = 1 AND track_stock = 1 AND kind = 'stock'"
            ' AND stock_qty_milli <= 0');
    }

    if (categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(categoryId);
    }
    if (!includeVariants) where.write(' AND parent_item_id IS NULL');

    if (kinds != null && kinds.isNotEmpty) {
      final String placeholders =
          List<String>.filled(kinds.length, '?').join(', ');
      where.write(' AND kind IN ($placeholders)');
      args.addAll(kinds.map((ItemKind k) => k.dbValue));
    }

    final String q = (text ?? '').trim();
    if (q.isNotEmpty) {
      // A variant matches on its own name too, so searching "red" finds it even
      // though the list normally shows only the group.
      where.write(' AND (name LIKE ? OR sku LIKE ? OR primary_barcode LIKE ?'
          ' OR variant_name LIKE ? OR scale_code = ?)');
      final String like = '%$q%';
      args
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(q);
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_items_full',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE, variant_name COLLATE NOCASE',
      limit: limit,
      offset: offset,
    );

    final Map<int, int> bundleCosts = await _bundleCosts(
      rows
          .where((Map<String, Object?> r) => '${r['kind']}' == 'bundle')
          .map((Map<String, Object?> r) => r['id'] as int)
          .toList(growable: false),
    );

    return rows
        .map((Map<String, Object?> m) => Item.fromMap(
              m,
              bundleCost: Money(bundleCosts[m['id'] as int] ?? 0),
            ))
        .toList();
  }

  Future<Item?> itemById(int id, {bool withUnits = true}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_items_full',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final List<ItemUnit> units =
        withUnits ? await unitsOfItem(id) : const <ItemUnit>[];
    final Map<int, int> costs = '${rows.first['kind']}' == 'bundle'
        ? await _bundleCosts(<int>[id])
        : const <int, int>{};

    return Item.fromMap(
      rows.first,
      units: units,
      bundleCost: Money(costs[id] ?? 0),
    );
  }

  Future<List<Item>> variantsOf(int groupItemId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_items_full',
      where: 'parent_item_id = ? AND is_active = 1',
      whereArgs: <Object?>[groupItemId],
      orderBy: 'variant_name COLLATE NOCASE, id',
    );

    // The picker needs prices, so the units come with them — one extra query
    // for the whole set rather than one per variant.
    final List<int> ids =
        rows.map((Map<String, Object?> r) => r['id'] as int).toList();
    final Map<int, List<ItemUnit>> units = await _unitsForItems(ids);

    return rows
        .map((Map<String, Object?> m) => Item.fromMap(
              m,
              units: units[m['id'] as int] ?? const <ItemUnit>[],
            ))
        .toList();
  }

  Future<ItemDraft> loadDraft(int? id) async {
    if (id == null) {
      return const ItemDraft(
        item: null,
        units: <ItemUnit>[],
        axes: <VariantAxis>[],
        parts: <BundlePart>[],
        variants: <Item>[],
      );
    }

    final Item? item = await itemById(id);
    if (item == null) {
      throw const AppFailure.notFound('That item no longer exists.');
    }

    return ItemDraft(
      item: item,
      units: item.units,
      axes: await axesOf(id),
      parts: await partsOf(id),
      variants: item.isGroup ? await variantsOf(id) : const <Item>[],
    );
  }

  Future<List<VariantAxis>> axesOf(int itemId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'item_variant_axes',
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
      orderBy: 'sort_order, id',
    );
    return rows.map(VariantAxis.fromMap).toList();
  }

  Future<List<BundlePart>> partsOf(int bundleItemId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT b.*,
             i.name           AS component_name,
             i.avg_cost_minor AS avg_cost_minor,
             IFNULL(iu.factor_milli, 1000) AS factor_milli,
             IFNULL(u.name, '')            AS unit_name
        FROM item_bundle_components b
        JOIN items i            ON i.id = b.component_item_id
        LEFT JOIN item_units iu ON iu.id = b.item_unit_id
        LEFT JOIN units u       ON u.id = iu.unit_id
       WHERE b.bundle_item_id = ?
       ORDER BY b.sort_order, b.id
      ''',
      <Object?>[bundleItemId],
    );
    return rows.map(BundlePart.fromMap).toList();
  }

  /// Resolves a scan, in the order a scanner actually produces them.
  ///
  /// Barcodes live on the *unit*, not on the item, so scanning the code printed
  /// on a carton adds a carton — with the carton's price — while scanning the
  /// piece adds a piece. In the old schema a barcode was one column on the item
  /// matched with `LIKE '%…%'`, so a single scan could match several products.
  Future<BarcodeHit?> resolveScan(String code) async {
    final String text = code.trim();
    if (text.isEmpty) return null;

    // 1. A scale label: it carries its own weight or price, so it has to be
    //    recognised before it is looked up as an ordinary barcode.
    final ScaleScan? scale = ScaleBarcode.parse(
      text,
      prefixes: _database
          .settingString('scale_prefixes', '20,21,22,23,24,25,26,27,28,29')
          .split(',')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false),
      payloadIsWeight:
          _database.settingString('scale_mode', 'weight') == 'weight',
      weightDecimals: _database.settingInt('scale_decimals', 3),
    );
    if (scale != null) {
      final List<Map<String, Object?>> byScale = await _database.db.query(
        'items',
        columns: <String>['id'],
        where: 'scale_code = ? AND is_active = 1',
        whereArgs: <Object?>[scale.itemCode],
        limit: 1,
      );
      if (byScale.isNotEmpty) {
        final Item? item = await itemById(byScale.first['id'] as int);
        if (item != null) {
          final ItemUnit? unit = item.saleUnit;
          final Qty qty = scale.isWeight
              ? scale.qty!
              : ScaleBarcode.quantityForAmount(
                  scale.amount!,
                  unit?.sellPrice ?? Money.zero,
                );
          return BarcodeHit(item: item, unit: unit, qty: qty);
        }
      }
      // A label whose product is not set up falls through to the plain lookups,
      // which will usually miss too — and the till then treats it as a search.
    }

    // 2. A unit barcode — the common case.
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT iu.*, u.name AS unit_name, iu.item_id AS owner_item_id
        FROM item_units iu
        JOIN units u  ON u.id = iu.unit_id
        JOIN items i  ON i.id = iu.item_id
       WHERE iu.barcode = ? AND i.is_active = 1
       LIMIT 1
      ''',
      <Object?>[text],
    );
    if (rows.isNotEmpty) {
      final ItemUnit unit = ItemUnit.fromMap(rows.first);
      final Item? item = await itemById(rows.first['owner_item_id'] as int);
      if (item != null) return BarcodeHit(item: item, unit: unit);
    }

    // 3. The item's own code, so an SKU typed by hand still works.
    final List<Map<String, Object?>> byItem = await _database.db.query(
      'items',
      columns: <String>['id'],
      where: 'sku = ? AND is_active = 1',
      whereArgs: <Object?>[text],
      limit: 1,
    );
    if (byItem.isEmpty) return null;

    final Item? item = await itemById(byItem.first['id'] as int);
    if (item == null) return null;
    return BarcodeHit(item: item, unit: item.saleUnit);
  }

  Future<List<ItemUnit>> unitsOfItem(int itemId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT iu.*, u.name AS unit_name
        FROM item_units iu
        JOIN units u ON u.id = iu.unit_id
       WHERE iu.item_id = ?
       ORDER BY iu.is_base DESC, iu.factor_milli, iu.sort_order
      ''',
      <Object?>[itemId],
    );
    return rows.map(ItemUnit.fromMap).toList();
  }

  Future<Map<int, List<ItemUnit>>> _unitsForItems(List<int> itemIds) async {
    if (itemIds.isEmpty) return <int, List<ItemUnit>>{};
    final String placeholders =
        List<String>.filled(itemIds.length, '?').join(', ');
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT iu.*, u.name AS unit_name
        FROM item_units iu
        JOIN units u ON u.id = iu.unit_id
       WHERE iu.item_id IN ($placeholders)
       ORDER BY iu.is_base DESC, iu.factor_milli, iu.sort_order
      ''',
      itemIds,
    );

    final Map<int, List<ItemUnit>> out = <int, List<ItemUnit>>{};
    for (final Map<String, Object?> r in rows) {
      final ItemUnit unit = ItemUnit.fromMap(r);
      out.putIfAbsent(unit.itemId, () => <ItemUnit>[]).add(unit);
    }
    return out;
  }

  Future<Map<int, int>> _bundleCosts(List<int> itemIds) async {
    if (itemIds.isEmpty) return <int, int>{};
    final String placeholders =
        List<String>.filled(itemIds.length, '?').join(', ');
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT item_id, cost_minor FROM v_bundle_costs '
      'WHERE item_id IN ($placeholders)',
      itemIds,
    );
    return <int, int>{
      for (final Map<String, Object?> r in rows)
        r['item_id'] as int: (r['cost_minor'] as num?)?.toInt() ?? 0,
    };
  }

  // ------------------------------------------------------------ saving ----

  Future<int> saveItem(ItemSaveRequest r) async {
    _validate(r);

    return _database.transaction<int>((Transaction txn) async {
      final String stamp = Time.stamp();

      // A service has nothing on a shelf; a bundle's stock lives in its parts;
      // a group is never sold at all. Only a plain stocked item is counted, and
      // forcing that here means no screen can save a contradiction.
      final bool tracks = r.kind == ItemKind.stock && r.trackStock;

      final Map<String, Object?> values = <String, Object?>{
        'sku': _nullIfBlank(r.sku),
        'name': r.name.trim(),
        'kind': r.kind.dbValue,
        'category_id': r.categoryId,
        'base_unit_id': r.baseUnitId,
        'description': _nullIfBlank(r.description),
        'image_path': _nullIfBlank(r.imagePath),
        'track_stock': tracks ? 1 : 0,
        'is_service': r.kind == ItemKind.service ? 1 : 0,
        'allow_negative': r.allowNegative ? 1 : 0,
        'reorder_level_milli': r.reorderLevelMilli,
        'tax_rate_bp': r.taxRateBp,
        'expiry_date': _nullIfBlank(r.expiryDate),
        'is_active': r.isActive ? 1 : 0,
        'parent_item_id': r.parentItemId,
        'variant_name': _nullIfBlank(r.variantName),
        'variant_attrs':
            r.variantAttrs.isEmpty ? null : Item.encodeAttrs(r.variantAttrs),
        'is_weighed': r.isWeighed ? 1 : 0,
        'track_batches': r.trackBatches && r.kind == ItemKind.stock ? 1 : 0,
        'scale_code': _nullIfBlank(r.scaleCode),
        'updated_at': stamp,
      };

      final int itemId;
      if (r.id == null) {
        values['created_at'] = stamp;
        itemId = await txn.insert('items', values);
      } else {
        itemId = r.id!;
        await txn.update('items', values,
            where: 'id = ?', whereArgs: <Object?>[itemId]);
      }

      await _replaceUnits(txn, itemId, r.units);
      await _replaceAxes(txn, itemId, r.kind, r.axes);
      await _replaceParts(txn, itemId, r.kind, r.parts);

      // Typing a cost is allowed exactly once: while the item has never been
      // bought and has never moved. After that, cost comes from purchases and
      // nothing else may touch it.
      final Money? opening = r.openingCost;
      if (opening != null) {
        final List<Map<String, Object?>> moved = await txn.rawQuery(
          'SELECT COUNT(*) AS n FROM stock_moves WHERE item_id = ?',
          <Object?>[itemId],
        );
        if ((moved.first['n'] as int? ?? 0) == 0) {
          await txn.update(
            'items',
            <String, Object?>{
              'avg_cost_minor': opening.minor,
              'last_cost_minor': opening.minor,
            },
            where: 'id = ?',
            whereArgs: <Object?>[itemId],
          );
        }
      }

      return itemId;
    });
  }

  void _validate(ItemSaveRequest r) {
    if (r.name.trim().isEmpty) {
      throw const AppFailure.validation('The item needs a name.');
    }

    if (r.kind == ItemKind.group) {
      if (r.axes.isEmpty) {
        throw const AppFailure.validation(
          'A product with variants needs at least one thing that varies — a '
          'size, a colour, a flavour.',
        );
      }
      for (final VariantAxis axis in r.axes) {
        if (axis.name.trim().isEmpty || axis.values.isEmpty) {
          throw const AppFailure.validation(
            'Give every variant axis a name and at least one value.',
          );
        }
      }
      // A group is not sold, so it needs no price — and must not be given one,
      // or the till would happily ring up "Shirt" with no size.
      return;
    }

    if (r.kind == ItemKind.bundle && r.parts.isEmpty) {
      throw const AppFailure.validation(
        'A bundle has to contain at least one item.',
      );
    }

    if (r.units.isEmpty) {
      throw const AppFailure.validation(
        'Give the item at least one unit with a price.',
      );
    }
    final int baseCount = r.units.where((ItemUnit u) => u.isBase).length;
    if (baseCount == 0) {
      throw const AppFailure.validation(
        'One of the units has to be the base unit.',
      );
    }
    if (baseCount > 1) {
      throw const AppFailure.validation('Only one unit can be the base unit.');
    }
    final ItemUnit base = r.units.firstWhere((ItemUnit u) => u.isBase);
    if (base.factorMilli != 1000) {
      throw const AppFailure.validation(
        'The base unit always has a factor of 1.',
      );
    }
    if (r.units.any((ItemUnit u) => u.factorMilli <= 0)) {
      throw const AppFailure.validation(
        'A unit has to contain more than zero of the base unit.',
      );
    }
    // Two units of the same kind on one item would make a barcode ambiguous.
    final Set<int> unitIds = r.units.map((ItemUnit u) => u.unitId).toSet();
    if (unitIds.length != r.units.length) {
      throw const AppFailure.validation(
        'The same unit is listed twice. Give each unit one line.',
      );
    }

    if (r.isWeighed) {
      final String code = (r.scaleCode ?? '').trim();
      if (code.isNotEmpty && !RegExp(r'^[0-9]{1,5}$').hasMatch(code)) {
        throw const AppFailure.validation(
          'A scale code is up to five digits — the number you program into the '
          'scale.',
        );
      }
    }
  }

  Future<void> _replaceUnits(
    Transaction txn,
    int itemId,
    List<ItemUnit> units,
  ) async {
    final List<Map<String, Object?>> existing = await txn.query(
      'item_units',
      columns: <String>['id'],
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    final Set<int> keep =
        units.map((ItemUnit u) => u.id).whereType<int>().toSet();

    for (final Map<String, Object?> row in existing) {
      final int rowId = row['id'] as int;
      if (keep.contains(rowId)) continue;
      // A unit that has been sold or bought is referenced by invoice lines. The
      // foreign key is ON DELETE SET NULL there, so history keeps its own copy
      // of the unit name and factor and nothing is lost.
      await txn.delete('item_units', where: 'id = ?', whereArgs: <Object?>[rowId]);
    }

    for (int i = 0; i < units.length; i++) {
      final ItemUnit u = units[i];
      final Map<String, Object?> data = u.toDb(itemId)..['sort_order'] = i;
      if (u.id == null) {
        await txn.insert('item_units', data);
      } else {
        await txn.update('item_units', data,
            where: 'id = ?', whereArgs: <Object?>[u.id]);
      }
    }
  }

  Future<void> _replaceAxes(
    Transaction txn,
    int itemId,
    ItemKind kind,
    List<VariantAxis> axes,
  ) async {
    await txn.delete('item_variant_axes',
        where: 'item_id = ?', whereArgs: <Object?>[itemId]);
    if (kind != ItemKind.group) return;

    for (int i = 0; i < axes.length; i++) {
      await txn.insert('item_variant_axes', axes[i].toDb(itemId)..['sort_order'] = i);
    }
  }

  Future<void> _replaceParts(
    Transaction txn,
    int itemId,
    ItemKind kind,
    List<BundlePart> parts,
  ) async {
    await txn.delete('item_bundle_components',
        where: 'bundle_item_id = ?', whereArgs: <Object?>[itemId]);
    if (kind != ItemKind.bundle) return;

    for (int i = 0; i < parts.length; i++) {
      await txn.insert(
        'item_bundle_components',
        parts[i].toDb(itemId)..['sort_order'] = i,
      );
    }
  }

  /// Builds every combination of the group's axes that does not exist yet.
  ///
  /// A shirt with `Size: S,M,L` and `Colour: Red,Blue` becomes six variants,
  /// each a real item with the group's units and prices copied onto it, so the
  /// shopkeeper only edits the ones that differ. Combinations that already
  /// exist are left exactly as they are — running this again after adding `XL`
  /// adds two rows and touches nothing else.
  Future<int> generateVariants(int groupItemId) async {
    final Item? group = await itemById(groupItemId);
    if (group == null) {
      throw const AppFailure.notFound('That product no longer exists.');
    }
    if (group.kind != ItemKind.group) {
      throw const AppFailure.validation(
        'Only a product marked as having variants can generate them.',
      );
    }

    final List<VariantAxis> axes = await axesOf(groupItemId);
    if (axes.isEmpty) return 0;

    final List<Map<String, String>> combinations = _combine(axes);
    if (combinations.isEmpty) return 0;
    if (combinations.length > 200) {
      throw AppFailure.validation(
        'That would create ${combinations.length} variants. Split the product '
        'up, or reduce the number of values.',
      );
    }

    final List<Item> existing = await variantsOf(groupItemId);
    final Set<String> taken = existing
        .map((Item v) => _attrKey(v.variantAttrs))
        .toSet();

    // Prices come from the group's own unit rows if it has them, and otherwise
    // from the first variant already created — either way a new size starts out
    // priced like its siblings rather than at zero.
    final List<ItemUnit> template = group.units.isNotEmpty
        ? group.units
        : (existing.isEmpty ? const <ItemUnit>[] : existing.first.units);

    int created = 0;
    for (final Map<String, String> combo in combinations) {
      if (taken.contains(_attrKey(combo))) continue;

      await saveItem(ItemSaveRequest(
        name: group.name,
        kind: ItemKind.stock,
        baseUnitId: group.baseUnitId,
        categoryId: group.categoryId,
        taxRateBp: group.taxRateBp,
        trackStock: true,
        allowNegative: group.allowNegative,
        imagePath: group.imagePath,
        parentItemId: groupItemId,
        variantName: combo.values.join(' / '),
        variantAttrs: combo,
        units: template
            .map((ItemUnit u) => u.copyWith(id: null, clearBarcode: true))
            .toList(growable: false),
      ));
      created++;
    }
    return created;
  }

  static List<Map<String, String>> _combine(List<VariantAxis> axes) {
    List<Map<String, String>> out = <Map<String, String>>[<String, String>{}];
    for (final VariantAxis axis in axes) {
      final List<Map<String, String>> next = <Map<String, String>>[];
      for (final Map<String, String> soFar in out) {
        for (final String value in axis.values) {
          next.add(<String, String>{...soFar, axis.name.trim(): value});
        }
      }
      out = next;
    }
    return out;
  }

  static String _attrKey(Map<String, String> attrs) {
    final List<String> keys = attrs.keys.toList()..sort();
    return keys.map((String k) => '$k=${attrs[k]}').join('|');
  }

  // ---------------------------------------------------------- removing ----

  /// Items are never deleted once they have moved — history has to stay
  /// readable — so this hides them instead, and only really deletes an item
  /// with no stock movement and no invoice line behind it.
  Future<void> removeItem(int id) async {
    await _database.transaction<void>((Transaction txn) async {
      final List<Map<String, Object?>> used = await txn.rawQuery(
        '''
        SELECT
          (SELECT COUNT(*) FROM stock_moves            WHERE item_id = ?) AS moves,
          (SELECT COUNT(*) FROM sales_invoice_lines    WHERE item_id = ?) AS sales,
          (SELECT COUNT(*) FROM purchase_invoice_lines WHERE item_id = ?) AS buys,
          (SELECT COUNT(*) FROM items                  WHERE parent_item_id = ?) AS variants,
          (SELECT COUNT(*) FROM item_bundle_components WHERE component_item_id = ?) AS inBundles
        ''',
        <Object?>[id, id, id, id, id],
      );
      final Map<String, Object?> c = used.first;

      if ((c['inBundles'] as int) > 0) {
        throw const AppFailure.conflict(
          'This item is part of a bundle. Take it out of the bundle first.',
        );
      }

      final bool hasHistory = (c['moves'] as int) > 0 ||
          (c['sales'] as int) > 0 ||
          (c['buys'] as int) > 0 ||
          (c['variants'] as int) > 0;

      if (hasHistory) {
        await txn.update(
          'items',
          <String, Object?>{'is_active': 0, 'updated_at': Time.stamp()},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        // Hiding a group hides what hangs off it, or the till would still offer
        // variants of a product that is no longer on sale.
        await txn.update(
          'items',
          <String, Object?>{'is_active': 0, 'updated_at': Time.stamp()},
          where: 'parent_item_id = ?',
          whereArgs: <Object?>[id],
        );
        return;
      }

      await txn.delete('item_units', where: 'item_id = ?', whereArgs: <Object?>[id]);
      await txn.delete('item_variant_axes',
          where: 'item_id = ?', whereArgs: <Object?>[id]);
      await txn.delete('item_bundle_components',
          where: 'bundle_item_id = ?', whereArgs: <Object?>[id]);
      await txn.delete('items', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  Future<void> setItemActive(int id, bool active) async {
    await _database.transaction<void>((Transaction txn) async {
      final String stamp = Time.stamp();
      await txn.update(
        'items',
        <String, Object?>{'is_active': active ? 1 : 0, 'updated_at': stamp},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.update(
        'items',
        <String, Object?>{'is_active': active ? 1 : 0, 'updated_at': stamp},
        where: 'parent_item_id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  // -------------------------------------------------------------- stock ----

  /// Sets an item's opening stock, or corrects it after a count. The difference
  /// is written as one adjustment movement **and** posted to the books, so the
  /// inventory account keeps matching the stock it represents.
  Future<void> adjustStock({
    required int itemId,
    required Qty counted,
    int? userId,
    String? note,
    bool isOpening = false,
  }) async {
    await _database.transaction<void>((Transaction txn) async {
      final StockAdjustment adj = await StockService.setCountedQuantity(
        txn,
        itemId: itemId,
        countedBaseMilli: counted.milli,
        userId: userId,
        note: note,
      );
      await Audit.write(
        txn,
        action: Audit.stockAdjust,
        entity: 'item',
        entityId: itemId,
        userId: userId,
        detail: 'counted ${counted.milli}, value ${adj.valueMinor}'
            '${note == null ? '' : ' · $note'}',
      );

      if (adj.valueMinor == 0) return;

      final int inventory =
          await AppDatabase.accountIdIn(txn, AccountKeys.inventory);
      final int counter = await AppDatabase.accountIdIn(
        txn,
        isOpening ? AccountKeys.openingEquity : AccountKeys.shrinkage,
      );

      await Journal.post(
        txn,
        sourceType: isOpening ? 'opening' : 'adjustment',
        sourceId: itemId,
        memo: note ?? (isOpening ? 'Opening stock' : 'Stock adjustment'),
        userId: userId,
        lines: adj.valueMinor > 0
            ? <JournalLine>[
                JournalLine.debit(inventory, adj.valueMinor),
                JournalLine.credit(counter, adj.valueMinor),
              ]
            : <JournalLine>[
                JournalLine.debit(counter, -adj.valueMinor),
                JournalLine.credit(inventory, -adj.valueMinor),
              ],
      );
    });
  }

  // ----------------------------------------------------------- history ----

  /// What this item's prices and costs have done.
  ///
  /// Two queries rather than a join: they answer different questions about
  /// different rows, and a join would multiply one against the other.
  Future<ItemHistory> history(int itemId, {int limit = 60}) async {
    final List<Map<String, Object?>> prices = await _database.db.query(
      'v_price_history',
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
      orderBy: 'changed_at DESC',
      limit: limit,
    );
    final List<Map<String, Object?>> costs = await _database.db.query(
      'v_cost_history',
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
      orderBy: 'moved_at DESC',
      limit: limit,
    );
    return ItemHistory(
      prices: prices.map(PriceChange.fromMap).toList(growable: false),
      costs: costs.map(CostPoint.fromMap).toList(growable: false),
    );
  }

  // --------------------------------------------------------- categories ----

  Future<List<Category>> categories({bool onlyActive = true}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT c.*,
             (SELECT COUNT(*) FROM items i
               WHERE i.category_id = c.id AND i.parent_item_id IS NULL)
               AS item_count
        FROM categories c
       ${onlyActive ? 'WHERE c.is_active = 1' : ''}
       ORDER BY c.sort_order, c.name COLLATE NOCASE
      ''',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<int> saveCategory(CategorySaveRequest r) async {
    if (r.name.trim().isEmpty) {
      throw const AppFailure.validation('The category needs a name.');
    }
    if (r.id != null && r.parentId == r.id) {
      throw const AppFailure.validation('A category cannot sit inside itself.');
    }

    final String stamp = Time.stamp();
    final Map<String, Object?> values = <String, Object?>{
      'name': r.name.trim(),
      'parent_id': r.parentId,
      'image_path': _nullIfBlank(r.imagePath),
      'color': _nullIfBlank(r.color),
      'sort_order': r.sortOrder,
      'is_active': r.isActive ? 1 : 0,
      'updated_at': stamp,
    };
    if (r.id == null) {
      values['created_at'] = stamp;
      return _database.db.insert('categories', values);
    }
    await _database.db.update('categories', values,
        where: 'id = ?', whereArgs: <Object?>[r.id]);
    return r.id!;
  }

  Future<void> removeCategory(int id) async {
    final List<Map<String, Object?>> inUse = await _database.db.query(
      'items',
      columns: <String>['id'],
      where: 'category_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (inUse.isNotEmpty) {
      throw const AppFailure.conflict(
        'That category still has items in it. Move them first, or hide the '
        'category instead of deleting it.',
      );
    }
    await _database.db
        .delete('categories', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // -------------------------------------------------------------- units ----

  Future<List<UnitDef>> units({bool onlyActive = true}) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT u.*,
             (SELECT COUNT(*) FROM item_units iu WHERE iu.unit_id = u.id)
               AS usage_count
        FROM units u
       ${onlyActive ? 'WHERE u.is_active = 1' : ''}
       ORDER BY u.name COLLATE NOCASE
      ''',
    );
    return rows.map(UnitDef.fromMap).toList();
  }

  Future<int> saveUnit(UnitSaveRequest r) async {
    if (r.name.trim().isEmpty) {
      throw const AppFailure.validation('The unit needs a name.');
    }
    final String stamp = Time.stamp();
    final Map<String, Object?> values = <String, Object?>{
      'name': r.name.trim(),
      'symbol': _nullIfBlank(r.symbol),
      'allow_fraction': r.allowFraction ? 1 : 0,
      'is_active': r.isActive ? 1 : 0,
      'updated_at': stamp,
    };
    if (r.id == null) {
      values['created_at'] = stamp;
      return _database.db.insert('units', values);
    }
    await _database.db
        .update('units', values, where: 'id = ?', whereArgs: <Object?>[r.id]);
    return r.id!;
  }

  Future<void> removeUnit(int id) async {
    final List<Map<String, Object?>> inUse = await _database.db.query(
      'item_units',
      columns: <String>['id'],
      where: 'unit_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (inUse.isNotEmpty) {
      throw const AppFailure.conflict('Items are still priced in that unit.');
    }
    await _database.db.delete('units', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  static String? _nullIfBlank(String? value) {
    final String text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
