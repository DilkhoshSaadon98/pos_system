import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/help/guide_content.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/app_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../core/theme/surfaces.dart';
import '../../core/widgets/form_fields.dart';
import '../../core/widgets/panels.dart';
import '../shell/presentation/cubit/shell_cubit.dart';
import '../shell/presentation/nav_entries.dart';

/// Which half of the guide is showing.
enum GuideView { screens, tasks }

class GuideState {
  const GuideState({
    this.view = GuideView.screens,
    this.query = '',
    this.selectedId = 'pos',
  });

  final GuideView view;
  final String query;

  /// The section shown in the right-hand pane on a wide screen.
  final String selectedId;

  GuideSection? get selected {
    for (final GuideSection s in guideSections) {
      if (s.id == selectedId) return s;
    }
    return guideSections.isEmpty ? null : guideSections.first;
  }

  List<GuideSection> sections(String language) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return guideSections;
    return guideSections
        .where((GuideSection s) => s.haystack(language).contains(q))
        .toList(growable: false);
  }

  List<GuideTask> tasks(String language) {
    final String q = query.trim().toLowerCase();
    final List<GuideTask> all = <GuideTask>[
      for (final GuideSection s in guideSections) ...s.tasks,
    ];
    if (q.isEmpty) return all;
    return all
        .where((GuideTask t) =>
            t.want.of(language).toLowerCase().contains(q) ||
            (t.how?.of(language).toLowerCase().contains(q) ?? false))
        .toList(growable: false);
  }

  GuideState copyWith({
    GuideView? view,
    String? query,
    String? selectedId,
  }) =>
      GuideState(
        view: view ?? this.view,
        query: query ?? this.query,
        selectedId: selectedId ?? this.selectedId,
      );
}

class GuideCubit extends Cubit<GuideState> {
  GuideCubit() : super(const GuideState());

  void search(String q) => emit(state.copyWith(query: q));

  void setView(GuideView v) => emit(state.copyWith(view: v));

  void select(String id) => emit(state.copyWith(selectedId: id));
}

/// The manual, inside the app.
///
/// Two ways in, because people arrive with two different questions. Somebody
/// exploring asks *what is this screen for*, and gets the list of screens.
/// Somebody with a job to do asks *how do I take money off a customer's debt*,
/// and does not know it is called a settlement — so the second half turns the
/// map upside down and is indexed by what a person wants, not by what the
/// feature is named.
///
/// Every entry ends at a button that opens the screen it describes. A manual
/// you have to read and then go and find the thing yourself is half a manual.
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GuideCubit, GuideState>(
      builder: (BuildContext context, GuideState state) {
        final GuideCubit cubit = context.read<GuideCubit>();
        final String language =
            Localizations.localeOf(context).languageCode;
        final bool mobile = Responsive.isMobile(context);
        final bool narrow = MediaQuery.sizeOf(context).width < 1100;

        final Widget header = Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 20, mobile ? 14 : 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: context.tr(AppText.guideTitle),
                subtitle: context.tr(AppText.guideSubtitle),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      controller: _search,
                      label: context.tr(AppText.guideSearchHint),
                      prefixIcon: Icons.search,
                      onChanged: cubit.search,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<GuideView>(
                showSelectedIcon: false,
                segments: <ButtonSegment<GuideView>>[
                  ButtonSegment<GuideView>(
                    value: GuideView.screens,
                    icon: const Icon(Icons.grid_view_outlined, size: 17),
                    label: Text(context.tr(AppText.guideScreens)),
                  ),
                  ButtonSegment<GuideView>(
                    value: GuideView.tasks,
                    icon: const Icon(Icons.checklist_rtl, size: 17),
                    label: Text(context.tr(AppText.guideTasks)),
                  ),
                ],
                selected: <GuideView>{state.view},
                onSelectionChanged: (Set<GuideView> s) =>
                    cubit.setView(s.first),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );

        if (state.view == GuideView.tasks) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: <Widget>[
                header,
                Expanded(child: _TaskList(state: state, language: language)),
              ],
            ),
          );
        }

        // Narrow: one list, tapping opens the detail as a page of its own.
        if (narrow) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: <Widget>[
                header,
                Expanded(
                  child: _SectionList(
                    state: state,
                    language: language,
                    onTap: (GuideSection s) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext pageContext) => Scaffold(
                          appBar: AppBar(title: Text(s.title.of(language))),
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: _Detail(section: s, language: language),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final GuideSection? selected = state.selected;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: <Widget>[
              header,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: 320,
                      child: _SectionList(
                        state: state,
                        language: language,
                        onTap: (GuideSection s) => cubit.select(s.id),
                      ),
                    ),
                    Expanded(
                      child: selected == null
                          ? const SizedBox.shrink()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 80),
                              child: _Detail(
                                section: selected,
                                language: language,
                              ),
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
  }
}

/// The screens, grouped the way the sidebar groups them.
class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.state,
    required this.language,
    required this.onTap,
  });

  final GuideState state;
  final String language;
  final ValueChanged<GuideSection> onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<GuideSection> sections = state.sections(language);

    if (sections.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: context.tr(AppText.noResults),
      );
    }

    String? lastGroup;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
      itemCount: sections.length,
      itemBuilder: (BuildContext context, int index) {
        final GuideSection s = sections[index];
        final bool newGroup = s.groupKey != lastGroup;
        lastGroup = s.groupKey;
        final bool selected = s.id == state.selectedId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (newGroup && s.groupKey.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                child: Text(
                  context.tr(s.groupKey).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.surfaces.muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            Material(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        s.icon,
                        size: 19,
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.title.of(language),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "I want to …" — the app indexed by intention.
class _TaskList extends StatelessWidget {
  const _TaskList({required this.state, required this.language});

  final GuideState state;
  final String language;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool mobile = Responsive.isMobile(context);
    final List<GuideTask> tasks = state.tasks(language);

    if (tasks.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: context.tr(AppText.noResults),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 0, mobile ? 14 : 24, 80),
      itemCount: tasks.length,
      itemBuilder: (BuildContext context, int index) {
        final GuideTask task = tasks[index];
        final GuideSection? section = _sectionOf(task.sectionId);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(section?.icon ?? Icons.help_outline,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.want.of(language),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          if (section != null) section.title.of(language),
                          if (task.how != null) task.how!.of(language),
                        ].join('  ·  '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.surfaces.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _OpenButton(sectionId: task.sectionId, compact: true),
              ],
            ),
          ),
        );
      },
    );
  }

  static GuideSection? _sectionOf(String id) {
    for (final GuideSection s in guideSections) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// One screen, explained in full.
class _Detail extends StatelessWidget {
  const _Detail({required this.section, required this.language});

  final GuideSection section;
  final String language;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(section.icon,
                  size: 24, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    section.title.of(language),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    section.purpose.of(language),
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.surfaces.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _OpenButton(sectionId: section.id),
          ],
        ),
        const SizedBox(height: 26),

        if (section.canDo.isNotEmpty) ...<Widget>[
          SectionHeader(dense: true, title: context.tr(AppText.guideCanDo)),
          const SizedBox(height: 8),
          for (final L line in section.canDo)
            _Bullet(text: line.of(language)),
          const SizedBox(height: 22),
        ],

        if (section.parts.isNotEmpty) ...<Widget>[
          SectionHeader(dense: true, title: context.tr(AppText.guideParts)),
          const SizedBox(height: 10),
          for (final GuidePart part in section.parts)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      part.title.of(language),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      part.body.of(language),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
                    if (part.actions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      for (final L line in part.actions)
                        _Bullet(text: line.of(language), dense: true),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
        ],

        if (section.tips.isNotEmpty)
          for (final L tip in section.tips)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.info
                    .withValues(alpha: theme.isDark ? 0.14 : 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip.of(language),
                      style:
                          theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
                  ),
                ],
              ),
            ),

        if (section.tasks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          SectionHeader(dense: true, title: context.tr(AppText.guideFromHere)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final GuideTask task in section.tasks)
                _TaskChip(task: task, language: language),
            ],
          ),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.dense = false});

  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 7, end: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: (dense
                      ? theme.textTheme.bodySmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes you to the screen being described.
///
/// The guide lives inside the shell, so it can ask the shell to change page.
/// Opened on its own — from a route, or a test — there is no shell to ask, and
/// the button simply is not drawn rather than throwing.
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.sectionId, this.compact = false});

  final String sectionId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ShellCubit? shell = _shellOf(context);
    if (shell == null) return const SizedBox.shrink();

    void go() => shell.goTo(sectionId, buildNavEntries());

    return compact
        ? IconButton.filledTonal(
            tooltip: context.tr(AppText.guideOpen),
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: go,
          )
        : FilledButton.icon(
            onPressed: go,
            icon: const Icon(Icons.open_in_new, size: 17),
            label: Text(context.tr(AppText.guideOpen)),
          );
  }

  static ShellCubit? _shellOf(BuildContext context) {
    try {
      return context.read<ShellCubit>();
    } on Object {
      return null;
    }
  }
}

class GuideRoutes {
  const GuideRoutes._();

  static const String path = '/guide';

  static Widget standalone() => BlocProvider<GuideCubit>(
        create: (_) => GuideCubit(),
        child: const GuidePage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        path: (_) => standalone(),
      };
}

/// A "you can do this from here" chip that actually goes there.
class _TaskChip extends StatelessWidget {
  const _TaskChip({required this.task, required this.language});

  final GuideTask task;
  final String language;

  @override
  Widget build(BuildContext context) {
    final ShellCubit? shell = _OpenButton._shellOf(context);
    return ActionChip(
      avatar: const Icon(Icons.arrow_forward, size: 15),
      label: Text(task.want.of(language)),
      onPressed:
          shell == null ? null : () => shell.goTo(task.sectionId, buildNavEntries()),
    );
  }
}
