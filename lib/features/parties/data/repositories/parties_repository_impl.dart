import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../../domain/entities/party.dart';
import '../../domain/repositories/parties_repository.dart';
import '../datasources/parties_local_datasource.dart';

class PartiesRepositoryImpl implements PartiesRepository {
  const PartiesRepositoryImpl(this._local);

  final PartiesLocalDataSource _local;

  @override
  Future<Result<List<Party>>> search({
    String? text,
    PartyKind? kind,
    bool onlyActive = true,
    bool onlyWithBalance = false,
    int limit = 300,
  }) =>
      guard(() => _local.search(
            text: text,
            kind: kind,
            onlyActive: onlyActive,
            onlyWithBalance: onlyWithBalance,
            limit: limit,
          ));

  @override
  Future<Result<Party?>> byId(int id) => guard(() => _local.byId(id));

  @override
  Future<Result<int>> save(PartySaveRequest request) =>
      guard(() => _local.save(request));

  @override
  Future<Result<Unit>> remove(int id) => guardVoid(() => _local.remove(id));

  @override
  Future<Result<List<StatementRow>>> statement(
    int partyId, {
    DateTime? from,
    DateTime? to,
  }) =>
      guard(() => _local.statement(partyId, from: from, to: to));

  @override
  Future<Result<List<OpenDocument>>> openDocuments(
    int partyId, {
    required bool isCustomer,
  }) =>
      guard(() => _local.openDocuments(partyId, isCustomer: isCustomer));

  @override
  Future<Result<int>> settle(SettlementRequest request) =>
      guard(() => _local.settle(request));
}
