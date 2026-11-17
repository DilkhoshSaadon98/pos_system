import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/guard.dart';
import '../../core/utils/time.dart';

/// One line of history.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.happenedAt,
    required this.action,
    required this.entity,
    this.entityId,
    this.detail,
    this.userName,
    this.username,
    this.shiftNo,
  });

  factory AuditEntry.fromRow(Map<String, Object?> m) => AuditEntry(
        id: m['id'] as int,
        happenedAt: '${m['happened_at']}',
        action: '${m['action']}',
        entity: '${m['entity']}',
        entityId: m['entity_id'] as int?,
        detail: m['detail'] as String?,
        userName: m['user_name'] as String?,
        username: m['username'] as String?,
        shiftNo: m['shift_no'] as String?,
      );

  final int id;
  final String happenedAt;

  /// What was done — `sale`, `sale_void`, `price_change`, `shift_close`…
  final String action;

  /// What it was done to — `sales_invoice`, `item`, `user`, `cash_shift`.
  final String entity;
  final int? entityId;

  /// The figures worth keeping: an invoice number, an amount, an old and a new
  /// price. Free text on purpose — a log that needs a schema change every time
  /// something new is worth recording ends up recording nothing.
  final String? detail;

  final String? userName;
  final String? username;
  final String? shiftNo;

  /// Actions that undo or overrule something, which is what an owner reading
  /// this screen is usually looking for.
  bool get isReversal =>
      action.endsWith('_void') ||
      action == 'sale_return' ||
      action == 'purchase_return' ||
      action == 'price_change' ||
      action == 'stock_adjust';
}

class AuditQuery {
  const AuditQuery({
    required this.from,
    required this.to,
    this.action,
    this.userId,
    this.search,
  });

  final DateTime from;
  final DateTime to;
  final String? action;
  final int? userId;
  final String? search;

  AuditQuery copyWith({
    DateTime? from,
    DateTime? to,
    String? action,
    bool clearAction = false,
    int? userId,
    bool clearUser = false,
    String? search,
  }) =>
      AuditQuery(
        from: from ?? this.from,
        to: to ?? this.to,
        action: clearAction ? null : (action ?? this.action),
        userId: clearUser ? null : (userId ?? this.userId),
        search: search ?? this.search,
      );
}

class AuditLocalDataSource {
  const AuditLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<AuditEntry>> search(AuditQuery q) async {
    final StringBuffer where = StringBuffer('happened_at BETWEEN ? AND ?');
    final List<Object?> args = <Object?>[
      Time.startOfDay(q.from),
      Time.endOfDay(q.to),
    ];

    if (q.action != null && q.action!.isNotEmpty) {
      where.write(' AND action = ?');
      args.add(q.action);
    }
    if (q.userId != null) {
      where.write(' AND user_id = ?');
      args.add(q.userId);
    }
    final String text = (q.search ?? '').trim();
    if (text.isNotEmpty) {
      where.write(' AND (detail LIKE ? OR entity LIKE ? OR user_name LIKE ?)');
      args
        ..add('%$text%')
        ..add('%$text%')
        ..add('%$text%');
    }

    final List<Map<String, Object?>> rows = await _database.db.query(
      'v_audit_log',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'happened_at DESC, id DESC',
      limit: 500,
    );
    return rows.map(AuditEntry.fromRow).toList(growable: false);
  }

  /// The actions that actually appear in this shop's history, so the filter
  /// offers real choices rather than a list of everything the code can write.
  Future<List<String>> actions() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      'SELECT DISTINCT action FROM audit_log ORDER BY action',
    );
    return rows
        .map((Map<String, Object?> r) => '${r['action']}')
        .toList(growable: false);
  }
}

abstract class AuditRepository {
  Future<Result<List<AuditEntry>>> search(AuditQuery query);
  Future<Result<List<String>>> actions();
}

class AuditRepositoryImpl implements AuditRepository {
  const AuditRepositoryImpl(this._local);

  final AuditLocalDataSource _local;

  @override
  Future<Result<List<AuditEntry>>> search(AuditQuery query) =>
      guard(() => _local.search(query));

  @override
  Future<Result<List<String>>> actions() => guard(_local.actions);
}

void initAuditInjection() {
  sl.registerLazySingleton<AuditLocalDataSource>(
    () => AuditLocalDataSource(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<AuditRepository>(
    () => AuditRepositoryImpl(sl<AuditLocalDataSource>()),
  );
}
