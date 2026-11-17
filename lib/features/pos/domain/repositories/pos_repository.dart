import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../entities/pos_line.dart';

abstract class PosRepository {
  PosConfig config();

  Future<Result<List<HeldCart>>> heldCarts();

  //? Parks the cart and returns the slot it was given.
  Future<Result<int>> hold({
    required List<PosLine> lines,
    required PriceMode priceMode,
    int? partyId,
    String? label,
    int? userId,
    int invoiceDiscountValue = 0,
    String invoiceDiscountKind = 'none',
    int serviceChargeMinor = 0,
  });
  //? resume cart
  Future<Result<ResumedCart>> resume(int cartId);
  //? discard cart
  Future<Result<Unit>> discard(int cartId);
}

class ResumedCart {
  const ResumedCart({
    required this.lines,
    required this.priceMode,
    this.partyId,
    this.invoiceDiscountKind = 'none',
    this.invoiceDiscountValue = 0,
    this.serviceChargeMinor = 0,
    this.missingItems = const <String>[],
  });

  final List<PosLine> lines;
  final PriceMode priceMode;
  final int? partyId;
  final String invoiceDiscountKind;
  final int invoiceDiscountValue;
  final int serviceChargeMinor;
  final List<String> missingItems;
}

class VariantChoice {
  const VariantChoice({required this.item, required this.unit});

  final Item item;
  final ItemUnit? unit;
}
