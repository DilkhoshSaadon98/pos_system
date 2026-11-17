import 'package:dartz/dartz.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/guard.dart';
import '../entities/party.dart';

abstract class PartiesRepository {
  Future<Result<List<Party>>> search({
    String? text,
    PartyKind? kind,
    bool onlyActive = true,
    bool onlyWithBalance = false,
    int limit = 300,
  });

  Future<Result<Party?>> byId(int id);

  Future<Result<int>> save(PartySaveRequest request);

  Future<Result<Unit>> remove(int id);

  /// Every posting that touched this party's account, with a running balance.
  Future<Result<List<StatementRow>>> statement(
    int partyId, {
    DateTime? from,
    DateTime? to,
  });

  /// Invoices of this party that still have something outstanding, oldest
  /// first — what a settlement screen offers to pay off.
  Future<Result<List<OpenDocument>>> openDocuments(
    int partyId, {
    required bool isCustomer,
  });

  Future<Result<int>> settle(SettlementRequest request);
}
