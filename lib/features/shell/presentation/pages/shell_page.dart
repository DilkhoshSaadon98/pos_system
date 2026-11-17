import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/localization/language_cubit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/modals.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../cubit/shell_cubit.dart';
import '../nav_entries.dart';


class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (BuildContext context, AuthState auth) {
        final UserRole role = auth.user?.role ?? UserRole.owner;
        final List<NavEntry> entries = buildNavEntries()
            .where((NavEntry e) => e.allows(role))
            .toList(growable: false);

        return BlocBuilder<ShellCubit, ShellState>(
          builder: (BuildContext context, ShellState state) {
            final int index = state.index.clamp(0, entries.length - 1);
            final NavEntry entry = entries[index];
            final ShellCubit cubit = context.read<ShellCubit>();

            if (Responsive.isMobile(context)) {
              return _MobileFrame(
                entries: entries,
                index: index,
                user: auth.user,
                onGo: cubit.go,
                child: entry.builder(),
              );
            }

            return Scaffold(
              body: Row(
                children: <Widget>[
                  _Rail(
                    entries: entries,
                    index: index,
                    expanded: state.railExpanded &&
                        Responsive.of(context).index >=
                            ScreenSize.desktop.index,
                    user: auth.user,
                    onGo: cubit.go,
                    onToggle: cubit.toggleRail,
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _TopBar(entry: entry, user: auth.user),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey<String>(entry.id),
                            child: entry.builder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.entries,
    required this.index,
    required this.expanded,
    required this.user,
    required this.onGo,
    required this.onToggle,
  });

  final List<NavEntry> entries;
  final int index;
  final bool expanded;
  final AppUser? user;
  final ValueChanged<int> onGo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: expanded ? 244 : 76,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: BorderDirectional(
          end: BorderSide(color: theme.surfaces.hairline),
        ),
      ),
      child: Column(
        children: <Widget>[
          _Brand(expanded: expanded, onToggle: onToggle),
          Divider(height: 1, color: theme.surfaces.hairline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: <Widget>[
                for (int i = 0; i < entries.length; i++) ...<Widget>[
                  if (expanded && _startsGroup(i))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: 12, top: 14, bottom: 6),
                      child: Text(
                        context.tr(entries[i].groupKey).toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.surfaces.muted,
                          letterSpacing: 0.8,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  if (!expanded && _startsGroup(i))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: theme.surfaces.hairline),
                    ),
                  _RailTile(
                    entry: entries[i],
                    selected: i == index,
                    expanded: expanded,
                    onTap: () => onGo(i),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: theme.surfaces.hairline),
          _UserTile(user: user, expanded: expanded),
        ],
      ),
    );
  }

  bool _startsGroup(int i) {
    final String group = entries[i].groupKey;
    if (group.isEmpty) return false;
    return i == 0 || entries[i - 1].groupKey != group;
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.point_of_sale, color: Colors.white, size: 20),
          ),
          if (expanded) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.tr(AppText.appTitle),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.tr(AppText.appSubtitle),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.menu_open, size: 20),
              onPressed: onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.entry,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final NavEntry entry;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        selected ? theme.colorScheme.primary : theme.surfaces.muted;

    final Widget tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : 0,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary
                .withValues(alpha: theme.isDark ? 0.18 : 0.10)
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: <Widget>[
          Icon(selected ? entry.activeIcon : entry.icon, size: 20, color: color),
          if (expanded) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr(entry.labelKey),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: expanded
            ? tile
            : Tooltip(message: context.tr(entry.labelKey), child: tile),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.expanded});

  final AppUser? user;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (user == null) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: <Widget>[
          CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.brand.withValues(alpha: 0.16),
            child: Text(
              user!.initials,
              style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          if (expanded) ...<Widget>[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    user!.fullName,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.tr(user!.role.labelKey),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr(AppText.navLogout),
              icon: const Icon(Icons.logout, size: 19),
              onPressed: () => _signOut(context),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _signOut(BuildContext context) async {
  final bool ok = await confirm(
    context,
    icon: Icons.logout,
    destructive: false,
    title: context.tr(AppText.navLogout),
    message: context.tr(AppText.loginSubtitle),
    confirmLabel: context.tr(AppText.navLogout),
  );
  if (ok && context.mounted) context.read<AuthCubit>().signOut();
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.entry, required this.user});

  final NavEntry entry;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.surfaces.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Icon(entry.activeIcon, size: 20, color: theme.surfaces.muted),
          const SizedBox(width: 10),
          Text(
            context.tr(entry.labelKey),
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          const _GuideButton(),
          const SizedBox(width: 4),
          const _LanguageButton(),
          const SizedBox(width: 4),
          const _ThemeButton(),
        ],
      ),
    );
  }
}

class _GuideButton extends StatelessWidget {
  const _GuideButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr(AppText.guideTitle),
      icon: const Icon(Icons.help_outline),
      onPressed: () =>
          context.read<ShellCubit>().goTo('guide', buildNavEntries()),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LanguageCubit, LanguageState>(
      builder: (BuildContext context, LanguageState state) {
        return PopupMenuButton<String>(
          tooltip: context.tr(AppText.settingsLanguage),
          icon: const Icon(Icons.translate, size: 20),
          initialValue: state.locale.languageCode,
          onSelected: (String code) =>
              context.read<LanguageCubit>().setLocale(Locale(code)),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            for (final MapEntry<String, String> e
                in AppLocalizations.languageNames.entries)
              PopupMenuItem<String>(value: e.key, child: Text(e.value)),
          ],
        );
      },
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LanguageCubit, LanguageState>(
      builder: (BuildContext context, LanguageState state) {
        final bool dark = state.themeMode == ThemeMode.dark;
        return IconButton(
          tooltip: context.tr(AppText.settingsTheme),
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20),
          onPressed: () => context
              .read<LanguageCubit>()
              .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
        );
      },
    );
  }
}

class _MobileFrame extends StatelessWidget {
  const _MobileFrame({
    required this.entries,
    required this.index,
    required this.user,
    required this.onGo,
    required this.child,
  });

  final List<NavEntry> entries;
  final int index;
  final AppUser? user;
  final ValueChanged<int> onGo;
  final Widget child;

  /// The four a phone gets a permanent button for. Everything else is one tap
  /// further away, in the drawer — a phone in a stockroom is used for counting
  /// and looking things up, not for the month-end accounts.
  static const List<String> _quick = <String>[
    'pos',
    'items',
    'sales',
    'dashboard',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<NavEntry> bar = <NavEntry>[
      for (final String id in _quick)
        ...entries.where((NavEntry e) => e.id == id),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(entries[index].labelKey)),
        actions: const <Widget>[
          _GuideButton(),
          _LanguageButton(),
          _ThemeButton(),
          SizedBox(width: 6),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: <Widget>[
              _UserTile(user: user, expanded: true),
              Divider(color: theme.surfaces.hairline),
              for (int i = 0; i < entries.length; i++)
                _RailTile(
                  entry: entries[i],
                  selected: i == index,
                  expanded: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onGo(i);
                  },
                ),
            ],
          ),
        ),
      ),
      body: KeyedSubtree(
        key: ValueKey<String>(entries[index].id),
        child: child,
      ),
      bottomNavigationBar: bar.length < 2
          ? null
          : NavigationBar(
              selectedIndex: bar.indexWhere(
                (NavEntry e) => e.id == entries[index].id,
              ).clamp(0, bar.length - 1),
              onDestinationSelected: (int i) =>
                  onGo(entries.indexOf(bar[i])),
              destinations: <Widget>[
                for (final NavEntry e in bar)
                  NavigationDestination(
                    icon: Icon(e.icon),
                    selectedIcon: Icon(e.activeIcon),
                    label: context.tr(e.labelKey),
                  ),
              ],
            ),
    );
  }
}
