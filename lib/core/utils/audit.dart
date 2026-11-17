import 'package:sqflite_common/sqlite_api.dart';

import '../shifts/shift_service.dart';
import 'time.dart';

/// Who did what, and when.
///
/// The audit log answers the question every shop owner eventually asks: *who
/// changed this price*, *who voided that invoice*, *who was on the till when
/// the drawer came up short*. It is written from inside the same transaction
/// as the thing it describes, so an action that was rolled back leaves no
/// trace claiming it happened — and an action that succeeded always has one.
///
/// Two deliberate limits:
///
/// * **It never throws.** A failure to write history must not undo a sale that
///   was otherwise fine, so every write is guarded. The cost of a missing line
///   is smaller than the cost of a refused sale.
/// * **It is append-only.** Nothing in the app updates or deletes a row here.
///   A log that can be edited is not evidence.
class Audit {
  const Audit._();

  /// Actions, spelled once so a screen can filter on them without guessing.
  static const String sale = 'sale';
  static const String saleReturn = 'sale_return';
  static const String saleVoid = 'sale_void';
  static const String purchase = 'purchase';
  static const String purchaseReturn = 'purchase_return';
  static const String purchaseVoid = 'purchase_void';
  static const String payment = 'payment';
  static const String stockAdjust = 'stock_adjust';
  static const String priceChange = 'price_change';
  static const String itemSave = 'item_save';
  static const String userSave = 'user_save';
  static const String userRemove = 'user_remove';
  static const String passwordSet = 'password_set';
  static const String signIn = 'sign_in';
  static const String settingsSave = 'settings_save';
  static const String shiftOpen = 'shift_open';
  static const String shiftClose = 'shift_close';
  static const String voucher = 'voucher';
  static const String backup = 'backup';
  static const String restore = 'restore';

  /// Records one action.
  ///
  /// [shiftId] is looked up when it is not given, so a caller that already
  /// knows the drawer does not pay for the query and one that does not still
  /// gets the tag.
  static Future<void> write(
    DatabaseExecutor db, {
    required String action,
    required String entity,
    int? entityId,
    int? userId,
    int? shiftId,
    String? detail,
  }) async {
    try {
      final int? shift =
          shiftId ?? await ShiftService.openShiftId(db, userId: userId);
      await db.insert('audit_log', <String, Object?>{
        'happened_at': Time.stamp(),
        'user_id': userId,
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'detail': detail,
        'shift_id': shift,
      });
    } catch (_) {
      // History is worth having, but never at the price of the thing that
      // made it. See the class comment.
    }
  }
}
