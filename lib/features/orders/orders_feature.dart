import 'package:dartz/dartz.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/exceptions.dart';
import '../../core/error/guard.dart';
import '../../core/money/money.dart';
import '../../core/utils/audit.dart';
import '../../core/utils/time.dart';

/// What was asked of a supplier.
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.orderNo,
    required this.partyId,
    required this.partyName,
    required this.orderedAt,
    required this.status,
    required this.total,
    required this.itemsCount,
    required this.orderedMilli,
    required this.receivedMilli,
    this.expectedAt,
    this.userName,
    this.note,
  });

  factory PurchaseOrder.fromRow(Map<String, Object?> m) => PurchaseOrder(
        id: m['id'] as int,
        orderNo: '${m['order_no']}',
        partyId: m['party_id'] as int,
        partyName: '${m['party_name'] ?? ''}',
        orderedAt: '${m['ordered_at']}',
        expectedAt: m['expected_at'] as String?,
        status: OrderStatus.fromDb(m['status']),
        total: Money.fromDb(m['total_minor']),
        itemsCount: m['items_count'] as int? ?? 0,
        orderedMilli: m['ordered_milli'] as int? ?? 0,
        receivedMilli: m['received_milli'] as int? ?? 0,
        userName: m['user_name'] as String?,
        note: m['note'] as String?,
      );

  final int id;
  final String orderNo;
  final int partyId;
  final String partyName;
  final String orderedAt;
  final String? expectedAt;
  final OrderStatus status;
  final Money total;
  final int itemsCount;

  /// Quantities across the whole order, so a list row can show how much of it
  /// has actually turned up.
  final int orderedMilli;
  final int receivedMilli;

  final String? userName;
  final String? note;

  bool get isOpen =>
      status == OrderStatus.draft ||
      status == OrderStatus.sent ||
      status == OrderStatus.partial;

  /// How complete the delivery is, in basis points — 10000 is everything.
  int get receivedBp =>
      orderedMilli == 0 ? 0 : (receivedMilli * 10000) ~/ orderedMilli;
}

enum OrderStatus {
  draft('draft'),
  sent('sent'),
  partial('partial'),
  received('received'),
  cancelled('cancelled');

  const OrderStatus(this.dbValue);

  final String dbValue;

  static OrderStatus fromDb(Object? v) => OrderStatus.values.firstWhere(
        (OrderStatus s) => s.dbValue == '$v',
        orElse: () => OrderStatus.draft,
      );
}

class OrderLine {
  const OrderLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.qtyMilli,
    required this.receivedQtyMilli,
    required this.unitCost,
    this.itemUnitId,
    this.unitName = '',
    this.factorMilli = 1000,
    this.note,
  });

  factory OrderLine.fromRow(Map<String, Object?> m) => OrderLine(
        id: m['id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name'] ?? ''}',
        qtyMilli: m['qty_milli'] as int? ?? 0,
        receivedQtyMilli: m['received_qty_milli'] as int? ?? 0,
        unitCost: Money.fromDb(m['unit_cost_minor']),
        itemUnitId: m['item_unit_id'] as int?,
        unitName: '${m['unit_name'] ?? ''}',
        factorMilli: m['factor_milli'] as int? ?? 1000,
        note: m['note'] as String?,
      );

  final int id;
  final int itemId;
  final String itemName;
  final int qtyMilli;
  final int receivedQtyMilli;
  final Money unitCost;
  final int? itemUnitId;
  final String unitName;
  final int factorMilli;
  final String? note;

  /// What is still owed by the supplier.
  int get outstandingMilli {
    final int left = qtyMilli - receivedQtyMilli;
    return left < 0 ? 0 : left;
  }

  bool get isComplete => outstandingMilli == 0;
}

/// One line as the editor hands it over.
class OrderLineInput {
  const OrderLineInput({
    required this.itemId,
    required this.qtyMilli,
    required this.unitCostMinor,
    this.itemUnitId,
    this.unitName = '',
    this.factorMilli = 1000,
    this.note,
  });

  final int itemId;
  final int qtyMilli;
  final int unitCostMinor;
  final int? itemUnitId;
  final String unitName;
  final int factorMilli;
  final String? note;

  int get totalMinor => (unitCostMinor * qtyMilli) ~/ 1000;
}

/// Ordering from suppliers.
///
/// ## An order is not an invoice, and this is the whole point
///
/// The old app had no way to say "I asked for twenty and six arrived". An
/// order here is a promise with quantities; receiving it creates a **purchase
/// invoice** through the ordinary purchase path — same landed costs, same
/// journal, same stock movements — and writes back how much of each line has
/// now arrived. The order stays open until the supplier has delivered it all,
/// so what is outstanding is a fact the shop can read rather than something
/// somebody remembers.
class OrdersLocalDataSource {
  const OrdersLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<PurchaseOrder>> search({
    required DateTime from,
    required DateTime to,
    int? partyId,
    bool onlyOpen = false,
  }) async {
    final StringBuffer where = StringBuffer('ordered_at BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[
      Time.startOfDay(from),
      Time.endOfDay(to),
    ];
    if (partyId != null) {
      where.write(' AND party_id = ?');
      args.add(partyId);
    }
    if (onlyOpen) {
      where.write(" AND status IN ('draft','sent','partial')");
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_purchase_orders_full',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'ordered_at DESC, id DESC',
    );
    return rows.map(PurchaseOrder.fromRow).toList(growable: false);
  }

  Future<List<OrderLine>> lines(int orderId) async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT l.*, i.name AS item_name
        FROM purchase_order_lines l
        JOIN items i ON i.id = l.item_id
       WHERE l.order_id = ?
       ORDER BY l.line_no, l.id
      ''',
      <Object?>[orderId],
    );
    return rows.map(OrderLine.fromRow).toList(growable: false);
  }

  /// Creates or replaces an order. Replacing rewrites the lines, which is only
  /// allowed while nothing has been received against them.
  Future<int> save({
    int? id,
    required int partyId,
    required List<OrderLineInput> lines,
    DateTime? expectedAt,
    int? userId,
    String? note,
    OrderStatus status = OrderStatus.draft,
  }) async {
    if (lines.isEmpty) {
      throw const AppFailure.validation('An order needs at least one item.');
    }

    return _database.transaction<int>((Transaction txn) async {
      final String stamp = Time.stamp();
      final int total = lines.fold(
          0, (int sum, OrderLineInput l) => sum + l.totalMinor);

      int orderId;
      if (id == null) {
        final String orderNo =
            await AppDatabase.nextDocumentNumber(txn, 'purchase_order');
        orderId = await txn.insert('purchase_orders', <String, Object?>{
          'order_no': orderNo,
          'party_id': partyId,
          'ordered_at': stamp,
          'expected_at': expectedAt == null ? null : Time.dayOf(expectedAt),
          'user_id': userId,
          'status': status.dbValue,
          'total_minor': total,
          'items_count': lines.length,
          'note': note,
          'created_at': stamp,
          'updated_at': stamp,
        });
      } else {
        orderId = id;
        final List<Map<String, Object?>> received = await txn.rawQuery(
          'SELECT IFNULL(SUM(received_qty_milli), 0) AS n '
          '  FROM purchase_order_lines WHERE order_id = ?',
          <Object?>[orderId],
        );
        if ((received.first['n'] as int? ?? 0) > 0) {
          throw const AppFailure.conflict(
            'Part of this order has already arrived, so its lines can no '
            'longer be changed. Cancel what is left instead.',
          );
        }

        await txn.update(
          'purchase_orders',
          <String, Object?>{
            'party_id': partyId,
            'expected_at': expectedAt == null ? null : Time.dayOf(expectedAt),
            'total_minor': total,
            'items_count': lines.length,
            'note': note,
            'status': status.dbValue,
            'updated_at': stamp,
          },
          where: 'id = ?',
          whereArgs: <Object?>[orderId],
        );
        await txn.delete('purchase_order_lines',
            where: 'order_id = ?', whereArgs: <Object?>[orderId]);
      }

      int lineNo = 0;
      for (final OrderLineInput l in lines) {
        await txn.insert('purchase_order_lines', <String, Object?>{
          'order_id': orderId,
          'item_id': l.itemId,
          'item_unit_id': l.itemUnitId,
          'unit_name': l.unitName,
          'factor_milli': l.factorMilli,
          'qty_milli': l.qtyMilli,
          'received_qty_milli': 0,
          'unit_cost_minor': l.unitCostMinor,
          'total_minor': l.totalMinor,
          'note': l.note,
          'line_no': lineNo++,
        });
      }

      await Audit.write(
        txn,
        action: 'order_save',
        entity: 'purchase_order',
        entityId: orderId,
        userId: userId,
        detail: '${lines.length} lines · $total',
      );

      return orderId;
    });
  }

  Future<void> setStatus(int orderId, OrderStatus status, {int? userId}) async {
    await _database.db.update(
      'purchase_orders',
      <String, Object?>{'status': status.dbValue, 'updated_at': Time.stamp()},
      where: 'id = ?',
      whereArgs: <Object?>[orderId],
    );
    await Audit.write(
      _database.db,
      action: 'order_status',
      entity: 'purchase_order',
      entityId: orderId,
      userId: userId,
      detail: status.dbValue,
    );
  }

  /// Records that an invoice fulfilled part of an order.
  ///
  /// Called by the purchase path after the invoice is posted, inside the same
  /// transaction: an order that says goods arrived when the invoice failed
  /// would be worse than one that says nothing.
  static Future<void> applyReceipt(
    DatabaseExecutor txn, {
    required int orderId,
    required int invoiceId,
    required Map<int, int> receivedByItem,
  }) async {
    final List<Map<String, Object?>> lines = await txn.query(
      'purchase_order_lines',
      where: 'order_id = ?',
      whereArgs: <Object?>[orderId],
      orderBy: 'line_no, id',
    );

    for (final Map<String, Object?> line in lines) {
      final int itemId = line['item_id'] as int;
      final int arrived = receivedByItem[itemId] ?? 0;
      if (arrived <= 0) continue;

      final int already = line['received_qty_milli'] as int? ?? 0;
      final int ordered = line['qty_milli'] as int? ?? 0;
      // Over-delivery is recorded as delivered in full rather than as more
      // than was ordered: the invoice already holds the real quantity, and a
      // line that reads 120 % complete helps nobody.
      final int now = already + arrived;
      await txn.update(
        'purchase_order_lines',
        <String, Object?>{'received_qty_milli': now > ordered ? ordered : now},
        where: 'id = ?',
        whereArgs: <Object?>[line['id']],
      );
    }

    final List<Map<String, Object?>> after = await txn.rawQuery(
      'SELECT IFNULL(SUM(qty_milli), 0) AS ordered, '
      '       IFNULL(SUM(received_qty_milli), 0) AS got '
      '  FROM purchase_order_lines WHERE order_id = ?',
      <Object?>[orderId],
    );
    final int ordered = after.first['ordered'] as int? ?? 0;
    final int got = after.first['got'] as int? ?? 0;

    await txn.update(
      'purchase_orders',
      <String, Object?>{
        'status': got >= ordered ? 'received' : 'partial',
        'updated_at': Time.stamp(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[orderId],
    );

    await txn.update(
      'purchase_invoices',
      <String, Object?>{'order_id': orderId},
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
    );
  }

  /// What each supplier last charged for an item — the number you want when
  /// deciding who to order from.
  Future<List<Map<String, Object?>>> supplierPrices({int? itemId, int? partyId}) {
    final StringBuffer where = StringBuffer('1 = 1');
    final List<Object?> args = <Object?>[];
    if (itemId != null) {
      where.write(' AND item_id = ?');
      args.add(itemId);
    }
    if (partyId != null) {
      where.write(' AND party_id = ?');
      args.add(partyId);
    }
    return _database.db.query(
      'v_supplier_prices',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'item_name, last_cost_minor',
    );
  }

  /// What a shop should reorder: below its level, with what it sells in a
  /// month and who last supplied it.
  Future<List<Map<String, Object?>>> reorderSuggestions() {
    return _database.db.rawQuery('''
      SELECT a.*,
             (SELECT p.party_id FROM v_supplier_prices p
               WHERE p.item_id = a.item_id
               ORDER BY p.last_bought_at DESC LIMIT 1) AS last_party_id,
             (SELECT p.party_name FROM v_supplier_prices p
               WHERE p.item_id = a.item_id
               ORDER BY p.last_bought_at DESC LIMIT 1) AS last_party_name,
             (SELECT p.last_cost_minor FROM v_supplier_prices p
               WHERE p.item_id = a.item_id
               ORDER BY p.last_bought_at DESC LIMIT 1) AS last_cost_minor
        FROM v_item_activity a
       WHERE a.reorder_level_milli > 0
         AND a.stock_qty_milli <= a.reorder_level_milli
       ORDER BY (a.reorder_level_milli - a.stock_qty_milli) DESC
    ''');
  }
}

abstract class OrdersRepository {
  Future<Result<List<PurchaseOrder>>> search({
    required DateTime from,
    required DateTime to,
    int? partyId,
    bool onlyOpen,
  });

  Future<Result<List<OrderLine>>> lines(int orderId);

  Future<Result<int>> save({
    int? id,
    required int partyId,
    required List<OrderLineInput> lines,
    DateTime? expectedAt,
    int? userId,
    String? note,
    OrderStatus status,
  });

  Future<Result<Unit>> setStatus(int orderId, OrderStatus status, {int? userId});

  Future<Result<List<Map<String, Object?>>>> supplierPrices({int? itemId});

  Future<Result<List<Map<String, Object?>>>> reorderSuggestions();
}

class OrdersRepositoryImpl implements OrdersRepository {
  const OrdersRepositoryImpl(this._local);

  final OrdersLocalDataSource _local;

  @override
  Future<Result<List<PurchaseOrder>>> search({
    required DateTime from,
    required DateTime to,
    int? partyId,
    bool onlyOpen = false,
  }) =>
      guard(() => _local.search(
            from: from,
            to: to,
            partyId: partyId,
            onlyOpen: onlyOpen,
          ));

  @override
  Future<Result<List<OrderLine>>> lines(int orderId) =>
      guard(() => _local.lines(orderId));

  @override
  Future<Result<int>> save({
    int? id,
    required int partyId,
    required List<OrderLineInput> lines,
    DateTime? expectedAt,
    int? userId,
    String? note,
    OrderStatus status = OrderStatus.draft,
  }) =>
      guard(() => _local.save(
            id: id,
            partyId: partyId,
            lines: lines,
            expectedAt: expectedAt,
            userId: userId,
            note: note,
            status: status,
          ));

  @override
  Future<Result<Unit>> setStatus(int orderId, OrderStatus status,
          {int? userId}) =>
      guardVoid(() => _local.setStatus(orderId, status, userId: userId));

  @override
  Future<Result<List<Map<String, Object?>>>> supplierPrices({int? itemId}) =>
      guard(() => _local.supplierPrices(itemId: itemId));

  @override
  Future<Result<List<Map<String, Object?>>>> reorderSuggestions() =>
      guard(_local.reorderSuggestions);
}

void initOrdersInjection() {
  sl.registerLazySingleton<OrdersLocalDataSource>(
    () => OrdersLocalDataSource(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<OrdersRepository>(
    () => OrdersRepositoryImpl(sl<OrdersLocalDataSource>()),
  );
}
