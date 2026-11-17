import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/database/app_database.dart';
import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/money/money.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/panels.dart';

/// One customer's debt, split by how old each part of it is.
class AgeingRow {
  const AgeingRow({
    required this.partyId,
    required this.name,
    required this.balance,
    required this.buckets,
    this.phone,
    this.creditLimit = Money.zero,
  });

  final int partyId;
  final String name;
  final String? phone;
  final Money balance;
  final Money creditLimit;

  /// One more than there are bucket edges: 0–30, 31–60, 61–90, older.
  final List<Money> buckets;

  bool get isOverLimit =>
      !creditLimit.isZero && balance.minor > creditLimit.minor;

  /// The oldest bucket carrying anything — what decides the order of the list,
  /// because a small very old debt is the one worth a phone call.
  int get worstBucket {
    for (int i = buckets.length - 1; i >= 0; i--) {
      if (buckets[i].isPositive) return i;
    }
    return 0;
  }
}

class AgeingState {
  const AgeingState({
    this.status = AppStatus.initial,
    this.rows = const <AgeingRow>[],
    this.edges = const <int>[30, 60, 90],
    this.failure,
  });

  final AppStatus status;
  final List<AgeingRow> rows;
  final List<int> edges;
  final Failure? failure;

  Money get total =>
      Money(rows.fold(0, (int s, AgeingRow r) => s + r.balance.minor));

  Money bucketTotal(int index) => Money(
      rows.fold(0, (int s, AgeingRow r) => s + r.buckets[index].minor));

  int get overLimit => rows.where((AgeingRow r) => r.isOverLimit).length;

  AgeingState copyWith({
    AppStatus? status,
    List<AgeingRow>? rows,
    List<int>? edges,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      AgeingState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        edges: edges ?? this.edges,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class AgeingCubit extends Cubit<AgeingState> {
  AgeingCubit(this._database) : super(const AgeingState());

  final AppDatabase _database;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final List<int> edges = _edges();
    final Result<List<AgeingRow>> rows = await guard(() => _build(edges));
    if (isClosed) return;

    final Failure? failure = rows.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            edges: edges,
            rows: rows.valueOr(const <AgeingRow>[]),
            clearFailure: true,
          ));
  }

  List<int> _edges() {
    final List<int> parsed = _database
        .settingString('ageing_buckets', '30,60,90')
        .split(',')
        .map((String s) => int.tryParse(s.trim()) ?? 0)
        .where((int n) => n > 0)
        .toList()
      ..sort();
    return parsed.isEmpty ? const <int>[30, 60, 90] : parsed;
  }

  /// Ages a balance against the invoices behind it.
  ///
  /// A payment in this app settles a customer's *balance*, not a numbered
  /// invoice, so which invoice is still open is a choice rather than a fact.
  /// The choice made here is the one every shop makes out loud: money that
  /// comes in pays off the oldest bill first, so what is still owed belongs to
  /// the newest invoices. Walking the invoices newest-first and filling them
  /// from the balance is that rule, written down.
  ///
  /// Anything left over when the invoices run out — an opening balance, a
  /// manual journal against the customer — is shown as current rather than
  /// silently dropped, because a total on this screen that disagrees with the
  /// customer's balance would make the whole report untrustworthy.
  Future<List<AgeingRow>> _build(List<int> edges) async {
    final List<Map<String, Object?>> parties =
        await _database.db.rawQuery('''
      SELECT p.id, p.name, p.phone, p.credit_limit_minor,
             IFNULL(b.balance_minor, 0) AS balance_minor
        FROM parties p
        LEFT JOIN v_party_balances b ON b.party_id = p.id
       WHERE p.kind IN ('customer', 'both')
         AND IFNULL(b.balance_minor, 0) > 0
       ORDER BY b.balance_minor DESC
    ''');
    if (parties.isEmpty) return const <AgeingRow>[];

    final List<Map<String, Object?>> invoices = await _database.db.rawQuery('''
      SELECT party_id, issued_at, due_minor
        FROM v_customer_invoices_due
       ORDER BY issued_at DESC
    ''');

    final Map<int, List<Map<String, Object?>>> byParty =
        <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> row in invoices) {
      byParty.putIfAbsent(row['party_id'] as int, () => <Map<String, Object?>>[])
          .add(row);
    }

    final DateTime today = DateTime.now();
    final List<AgeingRow> out = <AgeingRow>[];

    for (final Map<String, Object?> party in parties) {
      final int id = party['id'] as int;
      final List<int> buckets = List<int>.filled(edges.length + 1, 0);
      int left = party['balance_minor'] as int;

      for (final Map<String, Object?> invoice
          in byParty[id] ?? const <Map<String, Object?>>[]) {
        if (left <= 0) break;
        final int take = left < (invoice['due_minor'] as int)
            ? left
            : invoice['due_minor'] as int;
        left -= take;

        final DateTime? issued = DateTime.tryParse('${invoice['issued_at']}');
        final int age =
            issued == null ? 0 : today.difference(issued).inDays;

        int slot = edges.length;
        for (int i = 0; i < edges.length; i++) {
          if (age <= edges[i]) {
            slot = i;
            break;
          }
        }
        buckets[slot] += take;
      }

      if (left > 0) buckets[0] += left;

      out.add(AgeingRow(
        partyId: id,
        name: '${party['name']}',
        phone: party['phone'] as String?,
        balance: Money.fromDb(party['balance_minor']),
        creditLimit: Money.fromDb(party['credit_limit_minor']),
        buckets: buckets.map(Money.new).toList(growable: false),
      ));
    }

    // Worst first: the oldest debt at the top, and among equals the largest.
    out.sort((AgeingRow a, AgeingRow b) {
      final int byAge = b.worstBucket.compareTo(a.worstBucket);
      return byAge != 0 ? byAge : b.balance.minor.compareTo(a.balance.minor);
    });
    return out;
  }
}

/// Who owes, and for how long.
class AgeingPage extends StatelessWidget {
  const AgeingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AgeingCubit, AgeingState>(
      builder: (BuildContext context, AgeingState state) {
        final AgeingCubit cubit = context.read<AgeingCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(title: context.tr(AppText.ageingTitle)),
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
              else if (state.rows.isEmpty)
                EmptyState(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  message: context.tr(AppText.ageingNobody),
                )
              else ...<Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SizedBox(
                      width: mobile ? double.infinity : 230,
                      child: KpiCard(
                        label: context.tr(AppText.ageingTotal),
                        value: Fmt.money(state.total),
                        footnote: '${state.rows.length}',
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    for (int i = 0; i < state.edges.length + 1; i++)
                      SizedBox(
                        width: mobile ? double.infinity : 230,
                        child: KpiCard(
                          label: _bucketLabel(context, state.edges, i),
                          value: Fmt.money(state.bucketTotal(i)),
                          icon: Icons.schedule,
                          tint: _bucketTint(state.edges.length, i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                AdminTable<AgeingRow>(
                  rows: state.rows,
                  rowTint: (BuildContext context, AgeingRow row) =>
                      row.isOverLimit
                          ? AppColors.danger.withValues(alpha: 0.07)
                          : null,
                  mobileCard: (BuildContext context, AgeingRow row) =>
                      AdminRecordCard(
                    title: row.name,
                    subtitle: row.phone,
                    trailing: Text(Fmt.money(row.balance)),
                    details: <Widget>[
                      for (int i = 0; i < row.buckets.length; i++)
                        if (row.buckets[i].isPositive)
                          RecordDetail(
                            label: _bucketLabel(context, state.edges, i),
                            value: Fmt.money(row.buckets[i]),
                          ),
                    ],
                  ),
                  columns: <AdminColumn<AgeingRow>>[
                    AdminColumn<AgeingRow>(
                      label: context.tr(AppText.name),
                      flex: 5,
                      cell: (BuildContext context, AgeingRow row) => Row(
                        children: <Widget>[
                          Flexible(child: Text(row.name)),
                          if (row.isOverLimit) ...<Widget>[
                            const SizedBox(width: 8),
                            StatusChip(
                              label: context.tr(AppText.ageingOverLimit),
                              color: StatusChip.danger,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    for (int i = 0; i < state.edges.length + 1; i++)
                      AdminColumn<AgeingRow>(
                        label: _bucketLabel(context, state.edges, i),
                        flex: 3,
                        alignEnd: true,
                        hideBelow: i == 0 ? null : 900 + i * 60.0,
                        cell: (BuildContext context, AgeingRow row) => Text(
                          row.buckets[i].isZero
                              ? '—'
                              : Fmt.money(row.buckets[i]),
                          style: TextStyle(
                            color: _bucketTint(state.edges.length, i),
                            fontWeight: row.buckets[i].isPositive &&
                                    i == state.edges.length
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ),
                    AdminColumn<AgeingRow>(
                      label: context.tr(AppText.ageingTotal),
                      flex: 3,
                      alignEnd: true,
                      cell: (BuildContext context, AgeingRow row) => Text(
                        Fmt.money(row.balance),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
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

  static String _bucketLabel(
    BuildContext context,
    List<int> edges,
    int index,
  ) =>
      index < edges.length
          ? context.tr(AppText.ageingCurrent,
              params: <String, Object?>{'n': edges[index]})
          : context.tr(AppText.ageingOver,
              params: <String, Object?>{'n': edges.last});

  /// Green through to red as the debt gets older. The last bucket is the one
  /// that costs money, so it is the one that shouts.
  static Color? _bucketTint(int edgeCount, int index) {
    if (index == 0) return null;
    if (index == edgeCount) return AppColors.danger;
    return index == edgeCount - 1 ? AppColors.warning : AppColors.info;
  }
}

class AgeingRoutes {
  const AgeingRoutes._();

  static const String path = '/ageing';

  static Widget standalone() => BlocProvider<AgeingCubit>(
        create: (_) => AgeingCubit(sl<AppDatabase>())..load(),
        child: const AgeingPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
