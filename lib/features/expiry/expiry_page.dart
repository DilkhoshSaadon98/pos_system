import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/inventory/batch_service.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/money/money.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/panels.dart';

/// One batch on the shelf, with how long it has left.
class BatchRow {
  const BatchRow({
    required this.batchId,
    required this.itemId,
    required this.itemName,
    required this.qtyMilli,
    required this.unitCost,
    this.batchNo = '',
    this.expiryDate,
    this.partyName,
    this.daysLeft,
  });

  factory BatchRow.fromRow(Map<String, Object?> m) => BatchRow(
        batchId: m['batch_id'] as int,
        itemId: m['item_id'] as int,
        itemName: '${m['item_name']}',
        batchNo: '${m['batch_no'] ?? ''}',
        expiryDate: m['expiry_date'] as String?,
        qtyMilli: m['qty_milli'] as int? ?? 0,
        unitCost: Money.fromDb(m['unit_cost_minor']),
        partyName: m['party_name'] as String?,
        daysLeft: m['days_left'] as int?,
      );

  final int batchId;
  final int itemId;
  final String itemName;
  final String batchNo;
  final String? expiryDate;
  final int qtyMilli;
  final Money unitCost;
  final String? partyName;

  /// Negative when it has already gone.
  final int? daysLeft;

  bool get isExpired => (daysLeft ?? 1) < 0;

  /// What is at risk, at cost — the number that decides whether it is worth
  /// discounting the stock to move it.
  Money get value => Money((qtyMilli * unitCost.minor) ~/ 1000);
}

class ExpiryState {
  const ExpiryState({
    this.status = AppStatus.initial,
    this.rows = const <BatchRow>[],
    this.days = 30,
    this.failure,
  });

  final AppStatus status;
  final List<BatchRow> rows;
  final int days;
  final Failure? failure;

  List<BatchRow> get expired =>
      rows.where((BatchRow r) => r.isExpired).toList(growable: false);

  List<BatchRow> get soon =>
      rows.where((BatchRow r) => !r.isExpired).toList(growable: false);

  Money get expiredValue =>
      Money(expired.fold(0, (int s, BatchRow r) => s + r.value.minor));

  Money get soonValue =>
      Money(soon.fold(0, (int s, BatchRow r) => s + r.value.minor));

  ExpiryState copyWith({
    AppStatus? status,
    List<BatchRow>? rows,
    int? days,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      ExpiryState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        days: days ?? this.days,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class ExpiryCubit extends Cubit<ExpiryState> {
  ExpiryCubit(this._database) : super(const ExpiryState());

  final AppDatabase _database;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final int days = _database.settingInt('expiry_warn_days', 30);
    final Result<List<Map<String, Object?>>> rows = await guard(
      () => BatchService.expiring(_database.db, days: days),
    );
    if (isClosed) return;

    final Failure? failure = rows.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            days: days,
            rows: rows
                .valueOr(const <Map<String, Object?>>[])
                .map(BatchRow.fromRow)
                .toList(growable: false),
            clearFailure: true,
          ));
  }

  Future<void> setDays(int days) async {
    await _database.setSetting('expiry_warn_days', '$days');
    await load();
  }
}

/// What is about to go off.
///
/// Sorted by date rather than by value on purpose: the question this screen
/// answers is *what do I have to deal with first*, and that is always the
/// thing with the shortest date, however little it is worth.
class ExpiryPage extends StatelessWidget {
  const ExpiryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExpiryCubit, ExpiryState>(
      builder: (BuildContext context, ExpiryState state) {
        final ExpiryCubit cubit = context.read<ExpiryCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.expiryTitle),
                subtitle: context.tr(AppText.expiryWithin,
                    params: <String, Object?>{'n': state.days}),
                actions: <Widget>[
                  for (final int d in <int>[7, 30, 90])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: ChoiceChip(
                        label: Text('$d'),
                        selected: state.days == d,
                        onSelected: (_) => cubit.setDays(d),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (state.status.isFailure && state.failure != null)
                ErrorNotice(failure: state.failure!, onRetry: cubit.load)
              else ...<Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SizedBox(
                      width: mobile ? double.infinity : 250,
                      child: KpiCard(
                        label: context.tr(AppText.expiryExpired),
                        value: Fmt.money(state.expiredValue),
                        footnote: '${state.expired.length}',
                        icon: Icons.dangerous_outlined,
                        tint: state.expired.isEmpty ? null : AppColors.danger,
                      ),
                    ),
                    SizedBox(
                      width: mobile ? double.infinity : 250,
                      child: KpiCard(
                        label: context.tr(AppText.expirySoon),
                        value: Fmt.money(state.soonValue),
                        footnote: '${state.soon.length}',
                        icon: Icons.timelapse,
                        tint: state.soon.isEmpty ? null : AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AdminTable<BatchRow>(
                  rows: state.rows,
                  empty: EmptyState(
                    icon: Icons.event_available,
                    message: context.tr(AppText.expiryNothing),
                  ),
                  rowTint: (BuildContext context, BatchRow row) => row.isExpired
                      ? AppColors.danger.withValues(alpha: 0.07)
                      : null,
                  mobileCard: (BuildContext context, BatchRow row) =>
                      AdminRecordCard(
                    title: row.itemName,
                    subtitle: row.batchNo.isEmpty ? null : row.batchNo,
                    trailing: Text(Fmt.date(row.expiryDate)),
                    details: <Widget>[
                      RecordDetail(
                        label: context.tr(AppText.stock),
                        value: Fmt.qtyMilli(row.qtyMilli),
                      ),
                      RecordDetail(
                        label: context.tr(AppText.value),
                        value: Fmt.money(row.value),
                      ),
                    ],
                  ),
                  columns: <AdminColumn<BatchRow>>[
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.name),
                      flex: 5,
                      cell: (BuildContext context, BatchRow row) =>
                          Text(row.itemName),
                    ),
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.expiryBatch),
                      flex: 3,
                      hideBelow: 900,
                      cell: (BuildContext context, BatchRow row) =>
                          Text(row.batchNo.isEmpty ? '—' : row.batchNo),
                    ),
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.expiryDate),
                      flex: 3,
                      cell: (BuildContext context, BatchRow row) => Text(
                        Fmt.date(row.expiryDate),
                        style: TextStyle(
                          color: row.isExpired ? AppColors.danger : null,
                          fontWeight: row.isExpired ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.expiryDaysLeft),
                      flex: 2,
                      alignEnd: true,
                      cell: (BuildContext context, BatchRow row) => Text(
                        row.isExpired
                            ? context.tr(AppText.expiryGone)
                            : '${row.daysLeft ?? 0}',
                        style: TextStyle(
                          color: row.isExpired
                              ? AppColors.danger
                              : ((row.daysLeft ?? 99) <= 7
                                  ? AppColors.warning
                                  : null),
                        ),
                      ),
                    ),
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.stock),
                      flex: 2,
                      alignEnd: true,
                      cell: (BuildContext context, BatchRow row) =>
                          Text(Fmt.qtyMilli(row.qtyMilli)),
                    ),
                    AdminColumn<BatchRow>(
                      label: context.tr(AppText.value),
                      flex: 3,
                      alignEnd: true,
                      cell: (BuildContext context, BatchRow row) =>
                          Text(Fmt.money(row.value)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ExpiryRoutes {
  const ExpiryRoutes._();

  static const String path = '/expiry';

  static Widget standalone() => BlocProvider<ExpiryCubit>(
        create: (_) => ExpiryCubit(sl<AppDatabase>())..load(),
        child: const ExpiryPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
