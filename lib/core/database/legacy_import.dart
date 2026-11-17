import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../accounting/account_keys.dart';
import '../accounting/journal.dart';
import '../error/exceptions.dart';
import '../utils/time.dart';
import 'app_database.dart';

/// Brings an old `cashier_system.db` into the new schema.
///
/// What comes across, and why only this much:
///
/// * **Catalogue** — categories, units, items and their prices. Each item gets
///   a base unit plus whatever second unit it was sold in, so the multi-unit
///   pricing that used to live in three different columns becomes real rows.
/// * **People** — customers and suppliers, merged into one table.
/// * **Chart of accounts** — every account the shop had, with its Arabic name
///   and its place in the tree, attached to the new system accounts where the
///   two describe the same thing.
/// * **Opening balances, not history.** Old cash, bank and customer balances
///   come over as one opening entry each; old *postings* do not. This is
///   deliberate: the old ledger recorded every cash sale twice and booked
///   credit purchases backwards, so replaying it would import the errors along
///   with the data. Balances are taken at face value and can be corrected once,
///   at the start, which is far easier than untangling years of double counts.
/// * **Stock** — each item's counted quantity becomes an opening stock movement
///   valued at its last known cost.
/// * **Documents** — old sales invoices can optionally be copied over as
///   read-only history so the invoice list is not empty. They are marked
///   `imported` and carry no journal entry, because their value is already
///   inside the opening balances.
class LegacyImporter {
  const LegacyImporter({
    required this.newDb,
    required this.legacyPath,
    this.importInvoiceHistory = true,
    this.userId,
  });

  final AppDatabase newDb;
  final String legacyPath;
  final bool importInvoiceHistory;
  final int? userId;

  Future<LegacyImportReport> run() async {
    if (!File(legacyPath).existsSync()) {
      throw AppFailure.notFound('No database at $legacyPath');
    }

    final DatabaseFactory factory = AppDatabase.platformFactory();
    final Database old = await factory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    final LegacyImportReport report = LegacyImportReport();
    try {
      final Set<String> tables = await _tables(old);

      await newDb.transaction<void>((Transaction txn) async {
        final Map<int, int> unitMap = await _importUnits(old, txn, tables, report);
        final Map<int, int> categoryMap =
            await _importCategories(old, txn, tables, report);
        final Map<int, int> accountMap =
            await _importAccounts(old, txn, tables, report);
        final Map<int, int> itemMap = await _importItems(
            old, txn, tables, report, unitMap, categoryMap);
        final Map<int, int> partyMap =
            await _importParties(old, txn, tables, report, accountMap);

        await _importOpeningStock(old, txn, report, itemMap);
        await _importOpeningBalances(old, txn, tables, report, accountMap);

        if (importInvoiceHistory) {
          await _importSalesHistory(
              old, txn, tables, report, itemMap, partyMap);
        }
      });
    } finally {
      await old.close();
    }
    return report;
  }

  // ------------------------------------------------------------- discovery --

  static Future<Set<String>> _tables(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
    );
    return rows.map((Map<String, Object?> r) => '${r['name']}').toSet();
  }

  /// Reads the first column present out of [names] — the old file exists in
  /// several shapes (`items_name` in one version, `item_name` in the next) and
  /// the importer has to cope with all of them.
  static Object? _pick(Map<String, Object?> row, List<String> names) {
    for (final String n in names) {
      if (row.containsKey(n) && row[n] != null) return row[n];
    }
    return null;
  }

  static String _str(Map<String, Object?> row, List<String> names,
          [String fallback = '']) =>
      '${_pick(row, names) ?? fallback}';

  static double _num(Map<String, Object?> row, List<String> names,
      [double fallback = 0]) {
    final Object? v = _pick(row, names);
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  static int _money(Map<String, Object?> row, List<String> names) =>
      (_num(row, names) * 100).round();

  static int _milli(Map<String, Object?> row, List<String> names) =>
      (_num(row, names) * 1000).round();

  // ----------------------------------------------------------------- units --

  Future<Map<int, int>> _importUnits(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
  ) async {
    final Map<int, int> map = <int, int>{};
    if (!tables.contains('tbl_units')) return map;

    final List<Map<String, Object?>> rows = await old.query('tbl_units');
    final String stamp = Time.stamp();

    for (final Map<String, Object?> r in rows) {
      final String name = _str(r, <String>['unit_name', 'name']).trim();
      if (name.isEmpty) continue;
      final int oldId = (_pick(r, <String>['unit_id', 'id']) as num?)?.toInt() ?? 0;

      final List<Map<String, Object?>> existing = await txn.query(
        'units',
        columns: <String>['id'],
        where: 'name = ? COLLATE NOCASE',
        whereArgs: <Object?>[name],
        limit: 1,
      );
      final int newId = existing.isNotEmpty
          ? existing.first['id'] as int
          : await txn.insert('units', <String, Object?>{
              'name': name,
              'symbol': _str(r, <String>['unit_desc', 'symbol']),
              'allow_fraction': 0,
              'is_active': 1,
              'created_at': stamp,
              'updated_at': stamp,
            });
      map[oldId] = newId;
      report.units++;
    }
    return map;
  }

  // ------------------------------------------------------------ categories --

  Future<Map<int, int>> _importCategories(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
  ) async {
    final Map<int, int> map = <int, int>{};
    if (!tables.contains('tbl_categories')) return map;

    final List<Map<String, Object?>> rows = await old.query('tbl_categories');
    final String stamp = Time.stamp();

    for (final Map<String, Object?> r in rows) {
      final int oldId =
          (_pick(r, <String>['categories_id', 'id']) as num?)?.toInt() ?? 0;
      final String name =
          _str(r, <String>['categories_name', 'name'], 'Unnamed').trim();
      final int newId = await txn.insert('categories', <String, Object?>{
        'name': name.isEmpty ? 'Unnamed' : name,
        'image_path': _str(r, <String>['categories_image']),
        'sort_order': 0,
        'is_active': 1,
        'created_at': stamp,
        'updated_at': stamp,
      });
      map[oldId] = newId;
      report.categories++;
    }
    return map;
  }

  // -------------------------------------------------------------- accounts --

  /// Old ids that are known fixtures of the previous chart of accounts. They
  /// were hardcoded all over the old source, which is how we know what they
  /// meant.
  static const Map<int, String> _knownAccounts = <int, String>{
    7: AccountKeys.cash,
    8: AccountKeys.bank,
    9: AccountKeys.receivable,
    10: AccountKeys.inventory,
    20: AccountKeys.payable,
    34: AccountKeys.sales,
    44: AccountKeys.cogs,
    88: AccountKeys.retainedEarnings,
  };

  static const Map<String, String> _typeMap = <String, String>{
    'assets': 'asset',
    'asset': 'asset',
    'liabilities': 'liability',
    'liability': 'liability',
    'equity': 'equity',
    'revenues': 'revenue',
    'revenue': 'revenue',
    'expenses': 'expense',
    'expense': 'expense',
  };

  Future<Map<int, int>> _importAccounts(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
  ) async {
    final Map<int, int> map = <int, int>{};
    if (!tables.contains('tbl_accounts')) return map;

    final List<Map<String, Object?>> rows = await old.query(
      'tbl_accounts',
      orderBy: 'account_parent_id IS NOT NULL, account_id',
    );
    final String stamp = Time.stamp();

    // Accounts that already exist in the new chart, keyed by system key.
    final Map<String, int> system = <String, int>{};
    for (final Map<String, Object?> a in await txn.query(
      'accounts',
      columns: <String>['id', 'system_key'],
      where: "system_key IS NOT NULL AND system_key <> ''",
    )) {
      system['${a['system_key']}'] = a['id'] as int;
    }

    // Type roots, so an imported account always has somewhere to live.
    final Map<String, int> roots = <String, int>{};
    for (final Map<String, Object?> a in await txn.query(
      'accounts',
      columns: <String>['id', 'type'],
      where: 'parent_id IS NULL',
    )) {
      roots['${a['type']}'] = a['id'] as int;
    }

    for (final Map<String, Object?> r in rows) {
      final int oldId =
          (_pick(r, <String>['account_id', 'id']) as num?)?.toInt() ?? 0;
      final String name = _str(r, <String>['account_name', 'name']).trim();
      if (name.isEmpty) continue;

      final String oldType =
          _str(r, <String>['account_type', 'type'], 'asset').toLowerCase();
      final String type = _typeMap[oldType] ?? 'asset';

      // Anything we already own keeps its new identity; only the name is kept
      // from the old file, so the owner still recognises the account.
      final String? key = _knownAccounts[oldId];
      if (key != null && system.containsKey(key)) {
        map[oldId] = system[key]!;
        report.accountsMatched++;
        continue;
      }

      final int? oldParent =
          (_pick(r, <String>['account_parent_id']) as num?)?.toInt();
      final int parentId = (oldParent != null ? map[oldParent] : null) ??
          roots[type] ??
          roots['asset']!;

      final String normalSide =
          (type == 'asset' || type == 'expense') ? 'debit' : 'credit';

      final String baseCode = _str(r, <String>['account_code']).trim();
      final String code =
          baseCode.isEmpty ? 'L$oldId' : '$baseCode.$oldId';

      final int newId = await txn.insert('accounts', <String, Object?>{
        'code': code,
        'name': name,
        'name_ar': name,
        'type': type,
        'normal_side': normalSide,
        'parent_id': parentId,
        'is_group': 0,
        'is_active': 1,
        'note': 'Imported from the previous system (id $oldId)',
        'created_at': stamp,
        'updated_at': stamp,
      });
      map[oldId] = newId;
      report.accountsImported++;
    }
    return map;
  }

  // ----------------------------------------------------------------- items --

  Future<Map<int, int>> _importItems(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
    Map<int, int> unitMap,
    Map<int, int> categoryMap,
  ) async {
    final Map<int, int> map = <int, int>{};
    if (!tables.contains('tbl_items')) return map;

    final List<Map<String, Object?>> rows = await old.query('tbl_items');
    final String stamp = Time.stamp();

    final Set<String> usedBarcodes = <String>{};
    final Set<String> usedSkus = <String>{};

    for (final Map<String, Object?> r in rows) {
      final int oldId =
          (_pick(r, <String>['item_id', 'items_id', 'id']) as num?)?.toInt() ?? 0;
      final String name =
          _str(r, <String>['item_name', 'items_name'], 'Unnamed').trim();
      if (name.isEmpty) continue;

      final int? oldCat =
          (_pick(r, <String>['item_category_id', 'items_cat']) as num?)?.toInt();

      // Which unit becomes the base one.
      //
      // The old row named the unit it counted in (`unit_name`, say a box) and a
      // second, smaller unit (`alt_unit_name`, a piece) with how many of them
      // fit inside it (`unit_conversion`, six). The new schema wants the
      // *smallest* unit as the base, because every other factor is then a whole
      // multiple of it — a box is 6 pieces exactly, while a piece would be
      // 0.1666… of a box and every conversion would carry a rounding error.
      // So when the old row describes a bigger unit holding smaller ones, the
      // smaller one is promoted to base and the old one becomes a multiple.
      final String countedUnitName =
          _str(r, <String>['unit_name'], 'Piece').trim().isEmpty
              ? 'Piece'
              : _str(r, <String>['unit_name'], 'Piece').trim();
      final String altUnitName = _str(r, <String>['alt_unit_name']).trim();
      final double conversion = _num(r, <String>['unit_conversion'], 1);

      final bool promoteAlt = altUnitName.isNotEmpty &&
          altUnitName.toLowerCase() != countedUnitName.toLowerCase() &&
          conversion > 1;

      final String baseUnitName = promoteAlt ? altUnitName : countedUnitName;
      final int baseUnitId = await _unitIdByName(txn, baseUnitName, stamp);

      // Prices and stock in the old file are per counted unit; when the base
      // changes, both are divided by the conversion.
      final int countedSellPrice =
          _money(r, <String>['item_selling_price', 'items_selling']);
      final int countedWholesale =
          _money(r, <String>['item_wholesale_price', 'items_wholesaleprice']);
      final int basePrice = promoteAlt
          ? (countedSellPrice / conversion).round()
          : countedSellPrice;
      final int baseWholesale =
          promoteAlt ? (countedWholesale / conversion).round() : countedWholesale;

      final int countedCost =
          _money(r, <String>['item_cost_price', 'items_costprice']) != 0
              ? _money(r, <String>['item_cost_price', 'items_costprice'])
              : _money(r, <String>['item_buying_price', 'items_buingprice']);
      final int cost =
          promoteAlt ? (countedCost / conversion).round() : countedCost;

      String? sku = _str(r, <String>['item_code', 'sku']).trim();
      if (sku.isEmpty || usedSkus.contains(sku)) sku = null;
      if (sku != null) usedSkus.add(sku);

      final int newId = await txn.insert('items', <String, Object?>{
        'sku': sku,
        'name': name,
        'category_id': oldCat == null ? null : categoryMap[oldCat],
        'base_unit_id': baseUnitId,
        'description': _str(r, <String>['item_description', 'items_desc']),
        'image_path': _str(r, <String>['item_image']),
        'track_stock': 1,
        'is_service': 0,
        'allow_negative': 0,
        'avg_cost_minor': cost,
        'last_cost_minor': cost,
        'stock_qty_milli': 0,
        'reorder_level_milli': 0,
        'tax_rate_bp': 0,
        'production_date': _str(r, <String>['production_date']),
        'expiry_date': _str(r, <String>['expiry_date']),
        'is_active': 1,
        'created_at': _str(r, <String>['item_create_date'], stamp),
        'updated_at': stamp,
      });
      map[oldId] = newId;
      report.items++;

      // -- base unit, priced ------------------------------------------------
      String? barcode =
          _str(r, <String>['item_barcode', 'items_barcode']).trim();
      if (barcode.isEmpty || usedBarcodes.contains(barcode)) barcode = null;
      if (barcode != null) usedBarcodes.add(barcode);

      await txn.insert('item_units', <String, Object?>{
        'item_id': newId,
        'unit_id': baseUnitId,
        'factor_milli': 1000,
        'sell_price_minor': basePrice,
        'wholesale_price_minor': baseWholesale,
        'min_price_minor': 0,
        // The barcode printed on the old row belongs to the unit it was
        // counted in, so it follows that unit rather than the new base.
        'barcode': promoteAlt ? null : barcode,
        'is_base': 1,
        'is_default_sale': 1,
        'is_default_purchase': promoteAlt ? 0 : 1,
        'sort_order': 0,
      });

      // -- the bigger unit, when there was one ------------------------------
      if (promoteAlt) {
        final int bulkUnitId = await _unitIdByName(txn, countedUnitName, stamp);
        await txn.insert('item_units', <String, Object?>{
          'item_id': newId,
          'unit_id': bulkUnitId,
          'factor_milli': (conversion * 1000).round(),
          'sell_price_minor': countedSellPrice,
          'wholesale_price_minor': countedWholesale,
          'min_price_minor': 0,
          'barcode': barcode,
          'is_base': 0,
          'is_default_sale': 0,
          'is_default_purchase': 1,
          'sort_order': 1,
        });
        report.itemUnits++;
      }

      // -- extra unit prices, when that table was in use ---------------------
      if (tables.contains('tbl_units_price')) {
        final List<Map<String, Object?>> priced = await old.query(
          'tbl_units_price',
          where: 'item_id = ?',
          whereArgs: <Object?>[oldId],
        );
        for (final Map<String, Object?> p in priced) {
          final int? oldUnit =
              (_pick(p, <String>['unit_id']) as num?)?.toInt();
          final int? unitId = oldUnit == null ? null : unitMap[oldUnit];
          if (unitId == null || unitId == baseUnitId) continue;

          final double carton = _num(p, <String>['carton_quantity'], 1);
          String? code = _str(p, <String>['barcode']).trim();
          if (code.isEmpty || usedBarcodes.contains(code)) code = null;
          if (code != null) usedBarcodes.add(code);

          await txn.insert('item_units', <String, Object?>{
            'item_id': newId,
            'unit_id': unitId,
            'factor_milli': (carton <= 0 ? 1 : carton * 1000).round(),
            'sell_price_minor': _money(p, <String>['price', 'item_price']),
            'wholesale_price_minor': 0,
            'min_price_minor': 0,
            'barcode': code,
            'is_base': 0,
            'is_default_sale': 0,
            'is_default_purchase': 0,
            'sort_order': 2,
          });
          report.itemUnits++;
        }
      }
    }
    return map;
  }

  static Future<int> _unitIdByName(
    DatabaseExecutor txn,
    String name,
    String stamp,
  ) async {
    final List<Map<String, Object?>> rows = await txn.query(
      'units',
      columns: <String>['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: <Object?>[name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return txn.insert('units', <String, Object?>{
      'name': name,
      'allow_fraction': 0,
      'is_active': 1,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  // --------------------------------------------------------------- parties --

  Future<Map<int, int>> _importParties(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
    Map<int, int> accountMap,
  ) async {
    final Map<int, int> map = <int, int>{};
    final String stamp = Time.stamp();

    // Only the customer ids are kept in the returned map: they are the ones the
    // old invoice rows point at. Suppliers come across as parties too, but
    // nothing else references them by their old id.
    Future<void> importFrom(String table, String kind) async {
      if (!tables.contains(table)) return;
      final List<Map<String, Object?>> rows = await old.query(table);
      for (final Map<String, Object?> r in rows) {
        final int oldId = (_pick(r, <String>[
                  'users_id',
                  'supplier_id',
                  'id',
                ]) as num?)
                ?.toInt() ??
            0;
        final String name = _str(
          r,
          <String>['users_name', 'supplier_name', 'name'],
          'Unnamed',
        ).trim();
        if (name.isEmpty) continue;

        final int? oldAccount =
            (_pick(r, <String>['account_id']) as num?)?.toInt();

        final int newId = await txn.insert('parties', <String, Object?>{
          'name': name,
          'kind': kind,
          'phone': _str(r, <String>['users_phone', 'supplier_phone']),
          'phone2': _str(r, <String>['users_phone2', 'supplier_phone2']),
          'email': _str(r, <String>['users_email', 'supplier_email']),
          'address': _str(r, <String>['users_address', 'supplier_address']),
          'note': _str(r, <String>['users_note', 'supplier_note']),
          'account_id': oldAccount == null ? null : accountMap[oldAccount],
          'credit_limit_minor': 0,
          'is_active': 1,
          'created_at': _str(
            r,
            <String>['users_createdate', 'supplier_create_date'],
            stamp,
          ),
          'updated_at': stamp,
        });
        if (kind == 'customer') map[oldId] = newId;
        report.parties++;
      }
    }

    await importFrom('tbl_users', 'customer');
    await importFrom('tbl_supplier', 'supplier');
    return map;
  }

  // --------------------------------------------------------- opening stock --

  Future<void> _importOpeningStock(
    Database old,
    DatabaseExecutor txn,
    LegacyImportReport report,
    Map<int, int> itemMap,
  ) async {
    if (itemMap.isEmpty) return;
    final String stamp = Time.stamp();

    final List<Map<String, Object?>> rows = await old.query('tbl_items');
    int valueMinor = 0;

    for (final Map<String, Object?> r in rows) {
      final int oldId =
          (_pick(r, <String>['item_id', 'items_id', 'id']) as num?)?.toInt() ?? 0;
      final int? newId = itemMap[oldId];
      if (newId == null) continue;

      // The old file kept the same number in up to three columns. The one that
      // the cashier screen actually decremented is `item_count`, so that is the
      // count we trust.
      int qtyMilli = _milli(r, <String>[
        'item_count',
        'item_base_quantity',
        'items_count',
      ]);
      if (qtyMilli == 0) continue;

      // The count was in the unit the old row was counted in. If a smaller unit
      // became the base (see _importItems), the count grows by the same factor.
      final String countedUnit = _str(r, <String>['unit_name']).trim();
      final String altUnit = _str(r, <String>['alt_unit_name']).trim();
      final double conversion = _num(r, <String>['unit_conversion'], 1);
      if (altUnit.isNotEmpty &&
          altUnit.toLowerCase() != countedUnit.toLowerCase() &&
          conversion > 1) {
        qtyMilli = (qtyMilli * conversion).round();
      }

      // The old app let stock go negative and never corrected it. The number is
      // imported as it stands rather than quietly zeroed — but it is counted,
      // so the report can tell the owner which items need a recount.
      if (qtyMilli < 0) report.negativeStockItems++;

      final List<Map<String, Object?>> item = await txn.query(
        'items',
        columns: <String>['avg_cost_minor'],
        where: 'id = ?',
        whereArgs: <Object?>[newId],
        limit: 1,
      );
      final int cost = item.first['avg_cost_minor'] as int? ?? 0;
      final int lineValue = (cost * qtyMilli) ~/ 1000;

      await txn.insert('stock_moves', <String, Object?>{
        'item_id': newId,
        'moved_at': stamp,
        'kind': 'opening',
        'qty_milli': qtyMilli,
        'unit_cost_minor': cost,
        'cost_total_minor': lineValue,
        'balance_after_milli': qtyMilli,
        'doc_type': 'import',
        'user_id': userId,
        'note': 'Opening stock imported from the previous system',
      });
      valueMinor += lineValue;
      report.openingStockItems++;
    }

    if (valueMinor != 0) {
      await Journal.post(
        txn,
        sourceType: 'opening',
        memo: 'Opening stock (imported)',
        userId: userId,
        lines: <JournalLine>[
          JournalLine.debit(
            await AppDatabase.accountIdIn(txn, AccountKeys.inventory),
            valueMinor,
          ),
          JournalLine.credit(
            await AppDatabase.accountIdIn(txn, AccountKeys.openingEquity),
            valueMinor,
          ),
        ],
      );
      report.openingStockValueMinor = valueMinor;
    }
  }

  // ------------------------------------------------------ opening balances --

  Future<void> _importOpeningBalances(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
    Map<int, int> accountMap,
  ) async {
    if (!tables.contains('tbl_transactions') || accountMap.isEmpty) return;

    // Balance per old account, from the old single-line transaction table:
    // an account gains when it is the target and loses when it is the source.
    final List<Map<String, Object?>> rows = await old.rawQuery('''
      SELECT a.account_id,
             a.account_type,
             IFNULL((SELECT SUM(t.transaction_amount) FROM tbl_transactions t
                      WHERE t.target_account_id = a.account_id), 0)
           - IFNULL((SELECT SUM(t.transaction_amount) FROM tbl_transactions t
                      WHERE t.source_account_id = a.account_id), 0) AS raw_balance
        FROM tbl_accounts a
       WHERE NOT EXISTS (SELECT 1 FROM tbl_accounts c
                          WHERE c.account_parent_id = a.account_id)
    ''');

    final int openingEquity =
        await AppDatabase.accountIdIn(txn, AccountKeys.openingEquity);
    final int inventoryId =
        await AppDatabase.accountIdIn(txn, AccountKeys.inventory);

    final List<JournalLine> lines = <JournalLine>[];
    int net = 0;

    for (final Map<String, Object?> r in rows) {
      final int oldId = (r['account_id'] as num).toInt();
      final int? newId = accountMap[oldId];
      if (newId == null) continue;
      // Stock came over as real quantities; taking its old balance as well
      // would count the same goods twice.
      if (newId == inventoryId) continue;

      final int minor =
          (((r['raw_balance'] as num?)?.toDouble() ?? 0) * 100).round();
      if (minor == 0) continue;

      final String type = '${r['account_type']}'.toLowerCase();
      final bool debitNormal = type.startsWith('asset') || type.startsWith('expense');

      if (debitNormal == (minor > 0)) {
        lines.add(JournalLine.debit(newId, minor.abs()));
        net += minor.abs();
      } else {
        lines.add(JournalLine.credit(newId, minor.abs()));
        net -= minor.abs();
      }
      report.openingBalanceAccounts++;
    }

    if (lines.isEmpty) return;

    if (net > 0) {
      lines.add(JournalLine.credit(openingEquity, net));
    } else if (net < 0) {
      lines.add(JournalLine.debit(openingEquity, -net));
    }

    await Journal.post(
      txn,
      sourceType: 'opening',
      memo: 'Opening balances (imported)',
      userId: userId,
      lines: lines,
    );
    report.openingBalanceValueMinor = net;
  }

  // --------------------------------------------------------------- history --

  Future<void> _importSalesHistory(
    Database old,
    DatabaseExecutor txn,
    Set<String> tables,
    LegacyImportReport report,
    Map<int, int> itemMap,
    Map<int, int> partyMap,
  ) async {
    if (!tables.contains('tbl_invoice')) return;
    final String stamp = Time.stamp();

    final List<Map<String, Object?>> invoices =
        await old.query('tbl_invoice', orderBy: 'invoice_id');

    for (final Map<String, Object?> r in invoices) {
      final int oldId = (_pick(r, <String>['invoice_id']) as num?)?.toInt() ?? 0;
      final int total = _money(r, <String>['invoice_price']);
      final int cost = _money(r, <String>['invoice_cost']);
      final int? oldParty =
          (_pick(r, <String>['invoice_user_id']) as num?)?.toInt();
      final String issued =
          _str(r, <String>['invoice_createdate'], stamp).replaceAll(' ', 'T');
      final String payment =
          _str(r, <String>['invoice_payment'], 'cash').toLowerCase();
      final bool onCredit = payment.contains('dept') ||
          payment.contains('debt') ||
          payment.contains('credit');

      final int invoiceId = await txn.insert('sales_invoices', <String, Object?>{
        'invoice_no': 'OLD-${oldId.toString().padLeft(6, '0')}',
        'doc_type': 'sale',
        'party_id': oldParty == null ? null : partyMap[oldParty],
        'issued_at': issued,
        'user_id': userId,
        'price_mode': 'retail',
        'gross_minor': total,
        'subtotal_minor': total - _money(r, <String>['invoice_tax']),
        'discount_total_minor': _money(r, <String>['invoice_discount']),
        'invoice_discount_minor': _money(r, <String>['invoice_discount']),
        'tax_minor': _money(r, <String>['invoice_tax']),
        'total_minor': total,
        'paid_minor': onCredit ? 0 : total,
        'due_minor': 0,
        'cost_minor': cost,
        'profit_minor': total - cost,
        'items_count':
            (_pick(r, <String>['invoice_items_number']) as num?)?.toInt() ?? 0,
        'status': 'posted',
        'note': 'Imported history — not posted to the ledger',
        'created_at': stamp,
        'updated_at': stamp,
      });

      if (tables.contains('tbl_invoice_items')) {
        final List<Map<String, Object?>> lines = await old.query(
          'tbl_invoice_items',
          where: 'invoice_id = ?',
          whereArgs: <Object?>[oldId],
        );
        int lineNo = 0;
        for (final Map<String, Object?> l in lines) {
          final int? oldItem = (_pick(l, <String>['item_id']) as num?)?.toInt();
          final int? newItem = oldItem == null ? null : itemMap[oldItem];
          if (newItem == null) continue;
          final int qty = _milli(l, <String>['item_qty']);
          final int price = _money(l, <String>['item_price']);
          await txn.insert('sales_invoice_lines', <String, Object?>{
            'invoice_id': invoiceId,
            'item_id': newItem,
            'unit_name': _str(l, <String>['item_unit_name']),
            'factor_milli': 1000,
            'qty_milli': qty,
            'qty_base_milli': qty,
            'unit_price_minor': price,
            'gross_minor': (price * qty) ~/ 1000,
            'net_minor': (price * qty) ~/ 1000,
            'total_minor': (price * qty) ~/ 1000,
            'unit_cost_minor': _money(l, <String>['item_cost']),
            'cost_minor': (_money(l, <String>['item_cost']) * qty) ~/ 1000,
            'line_no': lineNo++,
          });
        }
      }
      report.invoices++;
    }
  }
}

class LegacyImportReport {
  int units = 0;
  int categories = 0;
  int items = 0;
  int itemUnits = 0;
  int parties = 0;
  int accountsImported = 0;
  int accountsMatched = 0;
  int openingStockItems = 0;
  int openingStockValueMinor = 0;
  int negativeStockItems = 0;
  int openingBalanceAccounts = 0;
  int openingBalanceValueMinor = 0;
  int invoices = 0;

  List<String> get summary => <String>[
        '$categories categories',
        '$units units',
        '$items items with ${items + itemUnits} unit prices',
        '$parties customers and suppliers',
        '$accountsImported accounts imported, $accountsMatched matched to the '
            'new chart',
        '$openingStockItems items with opening stock',
        if (negativeStockItems > 0)
          '$negativeStockItems items came over with negative stock — recount them',
        '$openingBalanceAccounts accounts with an opening balance',
        '$invoices historical invoices',
      ];
}
