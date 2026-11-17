import '../../../../core/error/guard.dart';
import '../entities/dashboard_snapshot.dart';


abstract class DashboardRepository {
  Future<Result<DashboardSnapshot>> load({DateTime? day});
}
