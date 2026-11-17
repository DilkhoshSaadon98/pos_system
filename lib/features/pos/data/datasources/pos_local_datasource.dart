import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/calc/discount.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/time.dart';
import '../../../catalog/data/datasources/catalog_local_datasource.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../domain/entities/pos_line.dart';
import '../../domain/repositories/pos_repository.dart';

/// Held carts, and the settings the till calculates with.
class PosLocalDataSource {
  PosLocalDataSource(this._database, this._catalog);

  final AppDatabase _database;
  final CatalogLocalDataSource _catalog;

  PosConfig config() => PosConfig(
        defaultTaxRateBp: _database.settingInt('default_tax_rate_bp'),
        pricesIncludeTax: _database.settingBool('prices_include_tax'),
        roundingStepMinor: _database.settingInt('rounding_step_minor'),
        defaultPriceMode:
            PriceMode.fromDb(_database.settingString('default_price_mode', 'retail')),
        autoPrint: _database.settingBool('auto_print_receipt', true),
        allowNegativeStock: _database.settingBool('allow_negative_stock'),
        cartSlots: _database.settingInt('cart_slots', 12),
        enforceMinPrice: _database.settingBool('enforce_min_price', true),
        shopName: _database.settingString('business_name'),
        enforceCreditLimit:
            _database.settingBool('enforce_credit_limit', true),
      );

  Future<List<HeldCart>> heldCarts() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT c.id, c.slot_no, c.label, c.created_at,
             p.name AS party_name,
             (SELECT COUNT(*) FROM cart_lines l WHERE l.cart_id = c.id)
               AS line_count,
             (SELECT IFNULL(SUM(l.unit_price_minor * l.qty_milli / 1000), 0)
                FROM cart_lines l WHERE l.cart_id = c.id) AS total_minor
        FROM carts c
        LEFT JOIN parties p ON p.id = c.party_id
       WHERE c.status = 'held'
       ORDER BY c.slot_no
    ''');
    return rows.map(HeldCart.fromMap).toList();
  }

  Future<int> hold({
    required List<PosLine> lines,
    required PriceMode priceMode,
    int? partyId,
    String? label,
    int? userId,
    int invoiceDiscountValue = 0,
    String invoiceDiscountKind = 'none',
    int serviceChargeMinor = 0,
  }) async {
    if (lines.isEmpty) {
      throw const AppFailure.validation('There is nothing to hold.');
    }

    return _database.transaction<int>((Transaction txn) async {
      final List<Map<String, Object?>> taken = await txn.query(
        'carts',
        columns: <String>['slot_no'],
        where: "status <> 'done'",
      );
      final Set<int> used =
          taken.map((Map<String, Object?> r) => r['slot_no'] as int).toSet();
      int slot = 1;
      while (used.contains(slot)) {
        slot++;
      }

      final String stamp = Time.stamp();
      final int cartId = await txn.insert('carts', <String, Object?>{
        'slot_no': slot,
        'label': label,
        'party_id': partyId,
        'price_mode': priceMode.dbValue,
        'status': 'held',
        'discount_kind': invoiceDiscountKind,
        'discount_value': invoiceDiscountValue,
        'tax_rate_bp': _database.settingInt('default_tax_rate_bp'),
        'service_charge_minor': serviceChargeMinor,
        'user_id': userId,
        'created_at': stamp,
        'updated_at': stamp,
      });

      for (int i = 0; i < lines.length; i++) {
        final PosLine l = lines[i];
        await txn.insert('cart_lines', <String, Object?>{
          'cart_id': cartId,
          'item_id': l.item.id,
          'item_unit_id': l.unit.id,
          'qty_milli': l.qty.milli,
          'unit_price_minor': l.unitPrice.minor,
          'discount_kind': l.discount.kind.name,
          'discount_value': l.discount.value,
          'is_gift': l.isGift ? 1 : 0,
          'note': l.note,
          'sort_order': i,
          'created_at': stamp,
        });
      }

      return slot;
    });
  }

  Future<ResumedCart> resume(int cartId) async {
    final List<Map<String, Object?>> head = await _database.db.query(
      'carts',
      where: 'id = ?',
      whereArgs: <Object?>[cartId],
      limit: 1,
    );
    if (head.isEmpty) {
      throw const AppFailure.notFound('That held sale is no longer there.');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'cart_lines',
      where: 'cart_id = ?',
      whereArgs: <Object?>[cartId],
      orderBy: 'sort_order',
    );

    final List<PosLine> lines = <PosLine>[];
    final List<String> missing = <String>[];

    for (final Map<String, Object?> r in rows) {
      final Item? item = await _catalog.itemById(r['item_id'] as int);
      if (item == null || !item.isActive) {
        missing.add('#${r['item_id']}');
        continue;
      }
      final ItemUnit? unit = item.unitById(r['item_unit_id'] as int?);
      if (unit == null) {
        missing.add(item.displayName);
        continue;
      }

      lines.add(PosLine(
        item: item,
        unit: unit,
        qty: Qty(r['qty_milli'] as int? ?? 1000),
        // The price the cart was held at is kept: it may have been typed by
        // hand, and re-pricing a customer's basket while they fetch one more
        // item is not something a shop wants to explain at the counter.
        unitPrice: Money.fromDb(r['unit_price_minor']),
        discount: DiscountSpec.fromDb(r['discount_kind'], r['discount_value']),
        isGift: (r['is_gift'] as int? ?? 0) == 1,
        note: r['note'] as String?,
      ));
    }

    await _database.transaction<void>((Transaction txn) async {
      await txn.delete('cart_lines',
          where: 'cart_id = ?', whereArgs: <Object?>[cartId]);
      await txn.delete('carts', where: 'id = ?', whereArgs: <Object?>[cartId]);
    });

    return ResumedCart(
      lines: lines,
      priceMode: PriceMode.fromDb(head.first['price_mode']),
      partyId: head.first['party_id'] as int?,
      invoiceDiscountKind: '${head.first['discount_kind'] ?? 'none'}',
      invoiceDiscountValue: head.first['discount_value'] as int? ?? 0,
      serviceChargeMinor: head.first['service_charge_minor'] as int? ?? 0,
      missingItems: missing,
    );
  }

  Future<void> discard(int cartId) async {
    await _database.transaction<void>((Transaction txn) async {
      await txn.delete('cart_lines',
          where: 'cart_id = ?', whereArgs: <Object?>[cartId]);
      await txn.delete('carts', where: 'id = ?', whereArgs: <Object?>[cartId]);
    });
  }
}
