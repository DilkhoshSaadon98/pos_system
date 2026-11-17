import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/widgets/admin_table.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/users_cubit.dart';

/// Who may use this till.
///
/// The roles are not decoration: a cashier sees no cost and no profit anywhere
/// in the app, an accountant has no till, and only an owner can reach this
/// screen. Every invoice, stock movement and journal entry records which of
/// them caused it.
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UsersCubit, UsersState>(
      listenWhen: (UsersState a, UsersState b) =>
          a.failure != b.failure && b.failure != null && b.status.isReady,
      listener: (BuildContext context, UsersState state) {
        AppSnack.error(context, state.failure!.detail);
        context.read<UsersCubit>().clearFailure();
      },
      builder: (BuildContext context, UsersState state) {
        final UsersCubit cubit = context.read<UsersCubit>();
        final AppUser? me = context.read<AuthCubit>().state.user;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Responsive.isMobile(context)
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(context, cubit, null),
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(context.tr(AppText.usersNew)),
                )
              : null,
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              20,
              Responsive.isMobile(context) ? 14 : 24,
              90,
            ),
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.usersTitle),
                subtitle: '${state.users.length}',
                actions: <Widget>[
                  if (!Responsive.isMobile(context))
                    FilledButton.icon(
                      onPressed: () => _edit(context, cubit, null),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: Text(context.tr(AppText.usersNew)),
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
                AdminTable<AppUser>(
                  rows: state.users,
                  onRowTap: (AppUser row) => _edit(context, cubit, row),
                  empty: EmptyState(
                    icon: Icons.people_outline,
                    message: context.tr(AppText.nothingYet),
                  ),
                  columns: <AdminColumn<AppUser>>[
                    AdminColumn<AppUser>(
                      label: context.tr(AppText.name),
                      flex: 4,
                      cell: (BuildContext context, AppUser row) => Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                AppColors.brand.withValues(alpha: 0.15),
                            child: Text(
                              row.initials,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  row.fullName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  row.username,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AdminColumn<AppUser>(
                      label: context.tr(AppText.usersRole),
                      flex: 3,
                      cell: (BuildContext context, AppUser row) => StatusChip(
                        compact: true,
                        label: context.tr(row.role.labelKey),
                        color: switch (row.role) {
                          UserRole.owner => AppColors.brand,
                          UserRole.manager => AppColors.info,
                          UserRole.accountant => AppColors.accent,
                          UserRole.cashier => AppColors.warning,
                        },
                      ),
                    ),
                    AdminColumn<AppUser>(
                      label: context.tr(AppText.usersLastLogin),
                      flex: 3,
                      hideBelow: 1000,
                      cell: (BuildContext context, AppUser row) => Text(
                        row.lastLoginAt == null
                            ? context.tr(AppText.usersNever)
                            : Fmt.dateTime(row.lastLoginAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    AdminColumn<AppUser>(
                      label: context.tr(AppText.status),
                      flex: 2,
                      cell: (BuildContext context, AppUser row) => StatusChip(
                        compact: true,
                        label: context.tr(
                          row.isActive ? AppText.active : AppText.inactive,
                        ),
                        color: row.isActive
                            ? AppColors.ok
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                    AdminColumn<AppUser>(
                      label: context.tr(AppText.actions),
                      flex: 2,
                      alignEnd: true,
                      cell: (BuildContext context, AppUser row) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: context.tr(AppText.edit),
                            icon: const Icon(Icons.edit_outlined, size: 19),
                            onPressed: () => _edit(context, cubit, row),
                          ),
                          IconButton(
                            tooltip: context.tr(AppText.delete),
                            icon: const Icon(Icons.delete_outline, size: 19),
                            color: AppColors.danger,
                            onPressed: row.id == me?.id
                                ? null
                                : () async {
                                    if (!await confirmDelete(context,
                                        what: row.fullName)) {
                                      return;
                                    }
                                    await cubit.remove(row.id,
                                        currentUserId: me?.id);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                  mobileCard: (BuildContext context, AppUser row) =>
                      AdminRecordCard(
                    onTap: () => _edit(context, cubit, row),
                    title: row.fullName,
                    subtitle: row.username,
                    trailing: StatusChip(
                      compact: true,
                      label: context.tr(row.role.labelKey),
                      color: AppColors.brand,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _edit(
    BuildContext context,
    UsersCubit cubit,
    AppUser? user,
  ) =>
      showAppModal<void>(
        context,
        width: 480,
        title: context.tr(user == null ? AppText.usersNew : AppText.usersEdit),
        subtitle: user?.fullName,
        builder: (BuildContext modalContext) =>
            _UserForm(cubit: cubit, user: user),
      );
}

class _UserForm extends StatefulWidget {
  const _UserForm({required this.cubit, this.user});

  final UsersCubit cubit;
  final AppUser? user;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.user?.fullName ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.user?.username ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.user?.phone ?? '');
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  late UserRole _role = widget.user?.role ?? UserRole.cashier;
  late bool _active = widget.user?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _name,
            autofocus: true,
            label: context.tr(AppText.usersFullName),
            prefixIcon: Icons.badge_outlined,
            validator: (String? v) => (v ?? '').trim().isEmpty
                ? context.tr(AppText.requiredField)
                : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _username,
            label: context.tr(AppText.loginUsername),
            prefixIcon: Icons.alternate_email,
            validator: (String? v) => (v ?? '').trim().isEmpty
                ? context.tr(AppText.requiredField)
                : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _phone,
            label: context.tr(AppText.phone),
            prefixIcon: Icons.call_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          AppDropdown<UserRole>(
            label: context.tr(AppText.usersRole),
            value: _role,
            items: UserRole.values,
            itemLabel: (UserRole r) => context.tr(r.labelKey),
            helper: context.tr(_role.hintKey),
            onChanged: (UserRole? r) => setState(() => _role = r ?? _role),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _password,
            label: context.tr(AppText.usersNewPassword),
            prefixIcon: Icons.lock_outline,
            obscure: true,
            helper: widget.user == null
                ? null
                : context.tr(AppText.usersKeepPassword),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _confirm,
            label: context.tr(AppText.usersConfirmPassword),
            prefixIcon: Icons.lock_outline,
            obscure: true,
          ),
          const SizedBox(height: 6),
          AppSwitchTile(
            icon: Icons.verified_user_outlined,
            title: context.tr(AppText.active),
            value: _active,
            onChanged: (bool v) => setState(() => _active = v),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(_role.hintKey),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          ModalActions(busy: _busy, onSave: _save),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String password = _password.text;
    if (password.isNotEmpty && password != _confirm.text) {
      AppSnack.error(context, context.tr(AppText.usersPasswordMismatch));
      return;
    }

    setState(() => _busy = true);
    final bool ok = await widget.cubit.save(
      id: widget.user?.id,
      fullName: _name.text,
      username: _username.text,
      role: _role,
      password: password.isEmpty ? null : password,
      phone: _phone.text,
      isActive: _active,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      AppSnack.success(context, context.tr(AppText.saved));
      Navigator.of(context).pop();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}
