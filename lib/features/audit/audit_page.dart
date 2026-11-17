import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/error/failures.dart';
import '../../core/error/guard.dart';
import '../../core/format/formatters.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/state/app_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/admin_table.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/panels.dart';
import 'audit_injection.dart';

class AuditState {
  const AuditState({
    this.status = AppStatus.initial,
    this.entries = const <AuditEntry>[],
    this.actions = const <String>[],
    required this.query,
    this.failure,
  });

  final AppStatus status;
  final List<AuditEntry> entries;

  /// The actions this shop has actually recorded.
  final List<String> actions;

  final AuditQuery query;
  final Failure? failure;

  AuditState copyWith({
    AppStatus? status,
    List<AuditEntry>? entries,
    List<String>? actions,
    AuditQuery? query,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      AuditState(
        status: status ?? this.status,
        entries: entries ?? this.entries,
        actions: actions ?? this.actions,
        query: query ?? this.query,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Reading the history.
class AuditCubit extends Cubit<AuditState> {
  AuditCubit(this._repository)
      : super(AuditState(
          query: AuditQuery(
            from: DateTime.now().subtract(const Duration(days: 7)),
            to: DateTime.now(),
          ),
        ));

  final AuditRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading, clearFailure: true));

    final Result<List<AuditEntry>> entries =
        await _repository.search(state.query);
    final Result<List<String>> actions = await _repository.actions();
    if (isClosed) return;

    final Failure? failure = entries.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    emit(state.copyWith(
      status: AppStatus.ready,
      entries: entries.valueOrNull,
      actions: actions.valueOr(const <String>[]),
      clearFailure: true,
    ));
  }

  Future<void> setRange(DateTime from, DateTime to) {
    emit(state.copyWith(query: state.query.copyWith(from: from, to: to)));
    return load();
  }

  Future<void> setAction(String? action) {
    emit(state.copyWith(
      query: action == null || action.isEmpty
          ? state.query.copyWith(clearAction: true)
          : state.query.copyWith(action: action),
    ));
    return load();
  }

  Future<void> setSearch(String text) {
    emit(state.copyWith(query: state.query.copyWith(search: text)));
    return load();
  }
}

/// Who did what.
///
/// The screen exists so that the answer to "who changed this price" is a
/// question anyone can ask themselves rather than one that has to be argued
/// about. Nothing here can be edited or deleted: a log a manager can tidy up
/// is not evidence, and the app never offers the option.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuditCubit, AuditState>(
      builder: (BuildContext context, AuditState state) {
        final AuditCubit cubit = context.read<AuditCubit>();
        final bool mobile = Responsive.isMobile(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 90),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.auditTitle),
                subtitle: '${state.entries.length}',
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(AppText.auditHint),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).surfaces.muted),
              ),
              const SizedBox(height: 16),

              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      controller: _search,
                      label: context.tr(AppText.search),
                      prefixIcon: Icons.search,
                      onSubmitted: cubit.setSearch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: AppDropdown<String>(
                      label: context.tr(AppText.auditAction),
                      value: state.query.action ?? '',
                      items: <String>['', ...state.actions],
                      itemLabel: (String a) =>
                          a.isEmpty ? context.tr(AppText.all) : _actionLabel(context, a),
                      onChanged: cubit.setAction,
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
              else
                AdminTable<AuditEntry>(
                  rows: state.entries,
                  empty: EmptyState(
                    icon: Icons.history,
                    message: context.tr(AppText.nothingYet),
                  ),
                  rowTint: (BuildContext context, AuditEntry row) =>
                      row.isReversal
                          ? AppColors.warning.withValues(alpha: 0.06)
                          : null,
                  mobileCard: (BuildContext context, AuditEntry row) =>
                      AdminRecordCard(
                    title: _actionLabel(context, row.action),
                    subtitle: Fmt.dateTime(row.happenedAt),
                    details: <Widget>[
                      RecordDetail(
                        label: context.tr(AppText.auditUser),
                        value: row.userName ?? '—',
                      ),
                      if (row.detail != null)
                        RecordDetail(
                          label: context.tr(AppText.auditDetail),
                          value: row.detail!,
                        ),
                    ],
                  ),
                  columns: <AdminColumn<AuditEntry>>[
                    AdminColumn<AuditEntry>(
                      label: context.tr(AppText.auditWhen),
                      flex: 3,
                      cell: (BuildContext context, AuditEntry row) =>
                          Text(Fmt.dateTime(row.happenedAt)),
                    ),
                    AdminColumn<AuditEntry>(
                      label: context.tr(AppText.auditAction),
                      flex: 3,
                      cell: (BuildContext context, AuditEntry row) => Text(
                        _actionLabel(context, row.action),
                        style: TextStyle(
                          fontWeight:
                              row.isReversal ? FontWeight.w700 : FontWeight.w500,
                          color: row.isReversal ? AppColors.warning : null,
                        ),
                      ),
                    ),
                    AdminColumn<AuditEntry>(
                      label: context.tr(AppText.auditUser),
                      flex: 3,
                      hideBelow: 900,
                      cell: (BuildContext context, AuditEntry row) =>
                          Text(row.userName ?? '—'),
                    ),
                    AdminColumn<AuditEntry>(
                      label: context.tr(AppText.shiftNumber),
                      flex: 2,
                      hideBelow: 1200,
                      cell: (BuildContext context, AuditEntry row) =>
                          Text(row.shiftNo ?? '—'),
                    ),
                    AdminColumn<AuditEntry>(
                      label: context.tr(AppText.auditDetail),
                      flex: 5,
                      cell: (BuildContext context, AuditEntry row) => Text(
                        row.detail ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// A machine name turned into something a shopkeeper reads. Unknown actions
  /// fall back to their own name rather than to a blank cell — a log that hides
  /// what it does not recognise is worse than one that is slightly ugly.
  static String _actionLabel(BuildContext context, String action) {
    switch (action) {
      case 'sale':
        return context.tr(AppText.auditActionSale);
      case 'sale_return':
        return context.tr(AppText.auditActionSaleReturn);
      case 'sale_void':
        return context.tr(AppText.auditActionSaleVoid);
      case 'purchase':
        return context.tr(AppText.auditActionPurchase);
      case 'purchase_return':
        return context.tr(AppText.auditActionPurchaseReturn);
      case 'purchase_void':
        return context.tr(AppText.auditActionPurchaseVoid);
      case 'payment':
        return context.tr(AppText.auditActionPayment);
      case 'stock_adjust':
        return context.tr(AppText.auditActionStockAdjust);
      case 'price_change':
        return context.tr(AppText.auditActionPriceChange);
      case 'item_save':
        return context.tr(AppText.auditActionItemSave);
      case 'user_save':
        return context.tr(AppText.auditActionUserSave);
      case 'user_remove':
        return context.tr(AppText.auditActionUserRemove);
      case 'password_set':
        return context.tr(AppText.auditActionPasswordSet);
      case 'sign_in':
        return context.tr(AppText.auditActionSignIn);
      case 'settings_save':
        return context.tr(AppText.auditActionSettingsSave);
      case 'shift_open':
        return context.tr(AppText.shiftOpen);
      case 'shift_close':
        return context.tr(AppText.shiftClose);
      case 'voucher':
        return context.tr(AppText.auditActionVoucher);
      case 'backup':
        return context.tr(AppText.settingsBackup);
      case 'restore':
        return context.tr(AppText.settingsRestore);
      default:
        return action;
    }
  }
}

class AuditRoutes {
  const AuditRoutes._();

  static const String path = '/audit';

  static Widget standalone() => BlocProvider<AuditCubit>(
        create: (_) => AuditCubit(sl<AuditRepository>())..load(),
        child: const AuditPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}
