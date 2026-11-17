import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/security/permissions.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/panels.dart';

class PermissionsState {
  const PermissionsState({
    this.status = AppStatus.initial,
    this.role = UserRole.cashier,
    this.allowed = const <String>{},
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final UserRole role;
  final Set<String> allowed;
  final bool busy;
  final Failure? failure;

  bool can(String key) => role == UserRole.owner || allowed.contains(key);

  PermissionsState copyWith({
    AppStatus? status,
    UserRole? role,
    Set<String>? allowed,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      PermissionsState(
        status: status ?? this.status,
        role: role ?? this.role,
        allowed: allowed ?? this.allowed,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

class PermissionsCubit extends Cubit<PermissionsState> {
  PermissionsCubit(this._database) : super(const PermissionsState());

  final AppDatabase _database;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));
    final Result<dynamic> result =
        await guardVoid(() => Permissions.instance.reload(_database.db));
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    emit(failure != null
        ? state.copyWith(status: AppStatus.failure, failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            allowed: Permissions.instance.forRole(state.role),
            clearFailure: true,
          ));
  }

  void setRole(UserRole role) => emit(state.copyWith(
        role: role,
        allowed: Permissions.instance.forRole(role),
      ));

  Future<void> toggle(String key, bool allowed) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result = await guardVoid(() => Permissions.set(
          _database.db,
          role: state.role,
          permission: key,
          allowed: allowed,
        ));
    if (isClosed) return;

    if (result.failed) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }

    // Reloaded rather than patched in memory: every screen in the app asks
    // this same object, and one stale copy would mean a cashier still seeing a
    // button they were just refused.
    await Permissions.instance.reload(_database.db);
    if (isClosed) return;
    emit(state.copyWith(
      busy: false,
      allowed: Permissions.instance.forRole(state.role),
    ));
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

/// What each role may do.
///
/// One switch per permission, grouped the way the app is: the till, the
/// catalogue, buying, money, the books. The owner's column is shown but locked
/// — an owner has every permission by definition, and a shop that can lock
/// itself out of its own books has a worse problem than a missing feature.
class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  static const Map<String, List<String>> _groups = <String, List<String>>{
    AppText.navPos: <String>[
      Perm.posUse,
      Perm.posDiscount,
      Perm.posBelowMinPrice,
      Perm.posOverCreditLimit,
      Perm.posReturn,
      Perm.posVoid,
    ],
    AppText.navGroupCatalog: <String>[
      Perm.itemsView,
      Perm.itemsEdit,
      Perm.itemsCost,
      Perm.stockAdjust,
      Perm.stockCount,
      Perm.promotionsEdit,
    ],
    AppText.navGroupBuy: <String>[
      Perm.purchasesView,
      Perm.purchasesEdit,
      Perm.ordersEdit,
    ],
    AppText.navGroupMoney: <String>[
      Perm.partiesView,
      Perm.partiesEdit,
      Perm.reportsView,
      Perm.reportsProfit,
      Perm.accountingView,
      Perm.accountingPost,
      Perm.shiftsCloseOther,
    ],
    AppText.navGroupSystem: <String>[
      Perm.settingsEdit,
      Perm.usersEdit,
      Perm.auditView,
    ],
  };

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PermissionsCubit, PermissionsState>(
      listenWhen: (PermissionsState a, PermissionsState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, PermissionsState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<PermissionsCubit>().clearFailure();
      },
      builder: (BuildContext context, PermissionsState state) {
        final PermissionsCubit cubit = context.read<PermissionsCubit>();
        final ThemeData theme = Theme.of(context);
        final bool mobile = Responsive.isMobile(context);
        final bool locked = state.role == UserRole.owner;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.permissionsTitle),
                subtitle: context.tr(AppText.permissionsHint),
              ),
              const SizedBox(height: 16),

              SegmentedButton<UserRole>(
                showSelectedIcon: false,
                segments: <ButtonSegment<UserRole>>[
                  for (final UserRole role in UserRole.values)
                    ButtonSegment<UserRole>(
                      value: role,
                      label: Text(context.tr(role.labelKey)),
                    ),
                ],
                selected: <UserRole>{state.role},
                onSelectionChanged: (Set<UserRole> s) => cubit.setRole(s.first),
              ),
              const SizedBox(height: 16),

              if (locked)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.shield_outlined,
                          size: 18, color: AppColors.info),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr(AppText.permissionsOwnerLocked),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

              if (state.status.isBusyFirstTime)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                for (final MapEntry<String, List<String>> group
                    in _groups.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SectionHeader(
                            dense: true,
                            title: context.tr(group.key),
                          ),
                          const SizedBox(height: 8),
                          for (final String key in group.value)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: state.can(key),
                              onChanged: locked || state.busy
                                  ? null
                                  : (bool v) => cubit.toggle(key, v),
                              title: Text(_label(context, key)),
                              subtitle: Text(
                                _hint(context, key),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.surfaces.muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  static String _label(BuildContext context, String key) => switch (key) {
        Perm.posUse => context.tr(AppText.permPosUse),
        Perm.posDiscount => context.tr(AppText.permPosDiscount),
        Perm.posBelowMinPrice => context.tr(AppText.permPosBelowMin),
        Perm.posOverCreditLimit => context.tr(AppText.permPosCredit),
        Perm.posReturn => context.tr(AppText.permPosReturn),
        Perm.posVoid => context.tr(AppText.permPosVoid),
        Perm.itemsView => context.tr(AppText.permItemsView),
        Perm.itemsEdit => context.tr(AppText.permItemsEdit),
        Perm.itemsCost => context.tr(AppText.permItemsCost),
        Perm.stockAdjust => context.tr(AppText.permStockAdjust),
        Perm.stockCount => context.tr(AppText.permStockCount),
        Perm.promotionsEdit => context.tr(AppText.permPromotions),
        Perm.purchasesView => context.tr(AppText.permPurchasesView),
        Perm.purchasesEdit => context.tr(AppText.permPurchasesEdit),
        Perm.ordersEdit => context.tr(AppText.permOrders),
        Perm.partiesView => context.tr(AppText.permPartiesView),
        Perm.partiesEdit => context.tr(AppText.permPartiesEdit),
        Perm.reportsView => context.tr(AppText.permReports),
        Perm.reportsProfit => context.tr(AppText.permProfit),
        Perm.accountingView => context.tr(AppText.permAccounting),
        Perm.accountingPost => context.tr(AppText.permAccountingPost),
        Perm.shiftsCloseOther => context.tr(AppText.permShiftsOther),
        Perm.settingsEdit => context.tr(AppText.permSettings),
        Perm.usersEdit => context.tr(AppText.permUsers),
        Perm.auditView => context.tr(AppText.permAudit),
        _ => key,
      };

  static String _hint(BuildContext context, String key) => switch (key) {
        Perm.posBelowMinPrice => context.tr(AppText.permPosBelowMinHint),
        Perm.posOverCreditLimit => context.tr(AppText.permPosCreditHint),
        Perm.itemsCost => context.tr(AppText.permItemsCostHint),
        Perm.reportsProfit => context.tr(AppText.permProfitHint),
        Perm.shiftsCloseOther => context.tr(AppText.permShiftsOtherHint),
        _ => key,
      };
}

class PermissionsRoutes {
  const PermissionsRoutes._();

  static const String path = '/permissions';

  static Widget standalone() => BlocProvider<PermissionsCubit>(
        create: (_) => PermissionsCubit(sl<AppDatabase>())..load(),
        child: const PermissionsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
