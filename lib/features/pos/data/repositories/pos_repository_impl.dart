import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../domain/entities/pos_line.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/pos_local_datasource.dart';

class PosRepositoryImpl implements PosRepository {
  const PosRepositoryImpl(this._local);

  final PosLocalDataSource _local;

  @override
  PosConfig config() => _local.config();

  @override
  Future<Result<List<HeldCart>>> heldCarts() => guard(_local.heldCarts);

  @override
  Future<Result<int>> hold({
    required List<PosLine> lines,
    required PriceMode priceMode,
    int? partyId,
    String? label,
    int? userId,
    int invoiceDiscountValue = 0,
    String invoiceDiscountKind = 'none',
    int serviceChargeMinor = 0,
  }) =>
      guard(() => _local.hold(
            lines: lines,
            priceMode: priceMode,
            partyId: partyId,
            label: label,
            userId: userId,
            invoiceDiscountValue: invoiceDiscountValue,
            invoiceDiscountKind: invoiceDiscountKind,
            serviceChargeMinor: serviceChargeMinor,
          ));

  @override
  Future<Result<ResumedCart>> resume(int cartId) =>
      guard(() => _local.resume(cartId));

  @override
  Future<Result<Unit>> discard(int cartId) =>
      guardVoid(() => _local.discard(cartId));
}
