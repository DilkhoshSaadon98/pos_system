import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/form_fields.dart';
import '../cubit/auth_cubit.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() => context
      .read<AuthCubit>()
      .signIn(_username.text, _password.text);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppColors.brandDeep.withValues(alpha: theme.isDark ? 0.35 : 0.14),
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: BlocBuilder<AuthCubit, AuthState>(
                  builder: (BuildContext context, AuthState state) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.point_of_sale,
                                color: AppColors.brand,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              context.tr(AppText.loginTitle),
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              context.tr(AppText.loginSubtitle),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 24),
                            AppTextField(
                              controller: _username,
                              autofocus: true,
                              label: context.tr(AppText.loginUsername),
                              prefixIcon: Icons.person_outline,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              controller: _password,
                              focusNode: _passwordFocus,
                              label: context.tr(AppText.loginPassword),
                              prefixIcon: Icons.lock_outline,
                              obscure: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                            ),
                            if (state.failure != null) ...<Widget>[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.danger
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(Icons.error_outline,
                                        size: 18, color: AppColors.danger),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        state.failure!.detail,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: AppColors.danger),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: state.busy ? null : _submit,
                              child: state.busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(context.tr(AppText.loginButton)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              context.tr(AppText.loginHint),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
