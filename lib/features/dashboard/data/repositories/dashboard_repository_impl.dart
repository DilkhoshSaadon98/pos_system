import '../../../../core/error/guard.dart';
import '../../domain/entities/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_local_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this._local);

  final DashboardLocalDataSource _local;

  @override
  Future<Result<DashboardSnapshot>> load({DateTime? day}) =>
      guard(() => _local.load(day: day));
}
