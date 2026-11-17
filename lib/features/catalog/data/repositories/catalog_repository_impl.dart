import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/money.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_local_datasource.dart';

/// The catalogue, with every exception turned into a [Failure] at the door.
///
/// There is deliberately no logic here beyond `guard` — if a rule ever needs a
/// decision, it belongs in the data source (where it can run inside the
/// transaction) or in the cubit (where it can talk to the user).
class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this._local);

  final CatalogLocalDataSource _local;

  @override
  Future<Result<List<Item>>> searchItems({
    String? text,
    int? categoryId,
    StockFilter filter = StockFilter.all,
    Set<ItemKind>? kinds,
    bool includeVariants = false,
    int limit = 300,
    int offset = 0,
  }) =>
      guard(() => _local.searchItems(
            text: text,
            categoryId: categoryId,
            filter: filter,
            kinds: kinds,
            includeVariants: includeVariants,
            limit: limit,
            offset: offset,
          ));

  @override
  Future<Result<Item?>> itemById(int id, {bool withUnits = true}) =>
      guard(() => _local.itemById(id, withUnits: withUnits));

  @override
  Future<Result<List<Item>>> variantsOf(int groupItemId) =>
      guard(() => _local.variantsOf(groupItemId));

  @override
  Future<Result<ItemDraft>> loadDraft(int? id) =>
      guard(() => _local.loadDraft(id));

  @override
  Future<Result<BarcodeHit?>> resolveScan(String code) =>
      guard(() => _local.resolveScan(code));

  @override
  Future<Result<List<ItemUnit>>> unitsOfItem(int itemId) =>
      guard(() => _local.unitsOfItem(itemId));

  @override
  Future<Result<int>> saveItem(ItemSaveRequest request) =>
      guard(() => _local.saveItem(request));

  @override
  Future<Result<int>> generateVariants(int groupItemId) =>
      guard(() => _local.generateVariants(groupItemId));

  @override
  Future<Result<Unit>> removeItem(int id) =>
      guardVoid(() => _local.removeItem(id));

  @override
  Future<Result<Unit>> setItemActive(int id, bool active) =>
      guardVoid(() => _local.setItemActive(id, active));

  @override
  Future<Result<Unit>> adjustStock({
    required int itemId,
    required Qty counted,
    int? userId,
    String? note,
    bool isOpening = false,
  }) =>
      guardVoid(() => _local.adjustStock(
            itemId: itemId,
            counted: counted,
            userId: userId,
            note: note,
            isOpening: isOpening,
          ));

  @override
  Future<Result<ItemHistory>> history(int itemId, {int limit = 60}) =>
      guard(() => _local.history(itemId, limit: limit));

  @override
  Future<Result<List<Category>>> categories({bool onlyActive = true}) =>
      guard(() => _local.categories(onlyActive: onlyActive));

  @override
  Future<Result<int>> saveCategory(CategorySaveRequest request) =>
      guard(() => _local.saveCategory(request));

  @override
  Future<Result<Unit>> removeCategory(int id) =>
      guardVoid(() => _local.removeCategory(id));

  @override
  Future<Result<List<UnitDef>>> units({bool onlyActive = true}) =>
      guard(() => _local.units(onlyActive: onlyActive));

  @override
  Future<Result<int>> saveUnit(UnitSaveRequest request) =>
      guard(() => _local.saveUnit(request));

  @override
  Future<Result<Unit>> removeUnit(int id) =>
      guardVoid(() => _local.removeUnit(id));
}
