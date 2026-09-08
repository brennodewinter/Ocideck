import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/learning_session.dart';
import '../../models/ociserve_models.dart';
import '../../state/ociserve_provider.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

class OciServeCoursesDialog extends ConsumerStatefulWidget {
  const OciServeCoursesDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const OciServeCoursesDialog(),
  );

  @override
  ConsumerState<OciServeCoursesDialog> createState() =>
      _OciServeCoursesDialogState();
}

class _OciServeCoursesDialogState extends ConsumerState<OciServeCoursesDialog> {
  static const _maxLessons = 500;

  String? _organizationId;
  bool _loading = true;
  String? _error;
  List<OciServeFeedItem> _lessons = const [];
  Map<String, OciServeLessonState> _progressByLesson = const {};
  String? _openingLessonId;
  OciServeFeedItem? _failedLesson;
  String? _selectedCourseVersionId;

  @override
  void initState() {
    super.initState();
    final memberships =
        ref.read(ociServeProvider).account?.activeMemberships ?? const [];
    _organizationId = memberships.isEmpty
        ? null
        : memberships.first.organizationId;
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final org = _organizationId;
    if (org == null) {
      setState(() {
        _loading = false;
        _error = 'no_organization';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifier = ref.read(ociServeProvider.notifier);
      final results = await Future.wait<Object>([
        notifier.learningFeed(org),
        notifier.learningState(org),
      ]);
      if (!mounted) return;
      final lessons = results[0] as List<OciServeFeedItem>;
      final progress = results[1] as OciServeLearningState;
      setState(() {
        if (lessons.length > _maxLessons) {
          _lessons = const [];
          _progressByLesson = const {};
          _error = 'too_many_lessons';
        } else {
          _lessons = lessons;
          _progressByLesson = {
            for (final state in progress.lessons)
              _progressKey(state.courseVersionId, state.lessonId): state,
          };
        }
        _loading = false;
        _selectedCourseVersionId = _preferredCourseVersion();
      });
    } catch (error, stack) {
      logError('OciServe: opleidingen laden', error.runtimeType, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'load_failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final account = ref.watch(ociServeProvider).account!;
    final memberships = account.activeMemberships;
    final available = MediaQuery.sizeOf(context);
    final compact = available.width < 760;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: available.height - 40,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) _sidebar(theme, palette, account.displayName),
            Expanded(
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(theme, palette, memberships, compact),
                    Expanded(child: _body(context.l10n, theme, palette)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(ThemeData theme, AppPalette palette, String displayName) {
    final l10n = context.l10n;
    final name = displayName.trim().isEmpty ? l10n.d('Cursist') : displayName;
    return SizedBox(
      width: 190,
      child: ColoredBox(
        color: palette.panel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      color: AppTheme.labelOn(theme.colorScheme.secondary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.d('eLearning'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.panelText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.panelText.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 19,
                        color: palette.panelText,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l10n.d('Mijn cursussen'),
                          style: TextStyle(
                            color: palette.panelText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Divider(color: palette.panelText.withValues(alpha: 0.18)),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: AppTheme.labelOn(
                      theme.colorScheme.secondary,
                    ),
                    child: Text(_initials(name)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.panelText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l10n.d('Cursist'),
                          style: TextStyle(
                            color: palette.panelText.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    AppPalette palette,
    List<OciServeMembership> memberships,
    bool compact,
  ) {
    final l10n = context.l10n;
    final account = ref.read(ociServeProvider).account!;
    final name = account.displayName.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 30, 24, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d('Mijn leeromgeving'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.accentInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  name.isEmpty
                      ? l10n.d('Mijn cursussen')
                      : l10n.d('Welkom, {naam}').replaceAll('{naam}', name),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  l10n.d(
                    'Ga verder waar u gebleven was, of kies een andere cursus die voor u klaarstaat.',
                  ),
                  style: TextStyle(color: palette.mutedText),
                ),
              ],
            ),
          ),
          if (memberships.length > 1 && !compact) ...[
            const SizedBox(width: 16),
            SizedBox(width: 210, child: _organizationPicker(memberships)),
          ],
          IconButton(
            tooltip: l10n.t('close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _organizationPicker(List<OciServeMembership> memberships) =>
      DropdownButtonFormField<String>(
        initialValue: _organizationId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.d('eLearning-organisatie'),
          isDense: true,
        ),
        items: [
          for (final membership in memberships)
            DropdownMenuItem(
              value: membership.organizationId,
              child: Text(
                membership.name.isEmpty
                    ? context.l10n.d('Organisatie')
                    : membership.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          _organizationId = value;
          _load();
        },
      );

  Widget _body(AppLocalizations l10n, ThemeData theme, AppPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _errorView(l10n, theme, palette);
    if (_lessons.isEmpty) {
      return _emptyView(
        l10n,
        theme,
        palette,
        Icons.school_outlined,
        l10n.d('Er staan geen opleidingen voor u klaar.'),
      );
    }

    final courses = _courses(l10n);
    final selected = courses.firstWhere(
      (course) => course.versionId == _selectedCourseVersionId,
      orElse: () => courses.first,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 28),
      children: [
        if (ref.watch(ociServeProvider).memberships.length > 1 &&
            MediaQuery.sizeOf(context).width < 760) ...[
          const SizedBox(height: 8),
          _organizationPicker(ref.watch(ociServeProvider).memberships),
          const SizedBox(height: 14),
        ],
        _featuredCourse(l10n, theme, palette, selected),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.d('Cursussen voor u'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              l10n
                  .d('{aantal} cursussen')
                  .replaceAll('{aantal}', '${courses.length}'),
              style: TextStyle(color: palette.mutedText, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth < 620
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final course in courses)
                  SizedBox(
                    width: cardWidth,
                    child: _courseCard(l10n, theme, palette, course),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _privacyNotice(l10n, theme, palette),
      ],
    );
  }

  Widget _featuredCourse(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    _Course course,
  ) {
    final next = course.nextLesson;
    final progress = course.fraction;
    final opening = _openingLessonId == next.lessonId;
    final buttonLabel = course.completed
        ? l10n.d('Opnieuw starten')
        : course.started
        ? l10n.d('Verdergaan')
        : l10n.d('Starten');
    return Container(
      key: const Key('ociserve-featured-course'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.panel.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.panelText.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  course.completed
                      ? Icons.workspace_premium_outlined
                      : course.started
                      ? Icons.play_circle_outline
                      : Icons.auto_awesome,
                  size: 17,
                  color: palette.panelText,
                ),
                const SizedBox(width: 6),
                Text(
                  course.completed
                      ? l10n.d('Afgerond')
                      : course.started
                      ? l10n.d('Nu bezig')
                      : l10n.d('Klaar om te beginnen'),
                  style: TextStyle(
                    color: palette.panelText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Text(
            course.title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: palette.panelText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            course.completed
                ? l10n.d('U kunt deze cursus opnieuw bekijken.')
                : course.started
                ? '${l10n.d('Verdergaan')}: ${next.title}'
                : l10n.d('Volgende: {les}').replaceAll('{les}', next.title),
            style: TextStyle(color: palette.panelText.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _completedLabel(l10n, course),
                  style: TextStyle(color: palette.panelText, fontSize: 12),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: palette.panelText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: palette.panelText.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
              semanticsLabel: l10n.d('Voortgang'),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openingLessonId == null ? () => _open(next) : null,
              icon: opening
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: AppTheme.labelOn(theme.colorScheme.secondary),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _courseCard(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    _Course course,
  ) {
    final selected = course.versionId == _selectedCourseVersionId;
    return Semantics(
      button: true,
      selected: selected,
      label: '${course.title}. ${_completedLabel(l10n, course)}',
      child: InkWell(
        onTap: () =>
            setState(() => _selectedCourseVersionId = course.versionId),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 190),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      course.completed
                          ? Icons.workspace_premium_outlined
                          : Icons.shield_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  _statusChip(l10n, theme, course),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                course.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 16,
                    color: palette.mutedText,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    l10n
                        .d('{aantal} lessen')
                        .replaceAll('{aantal}', '${course.lessons.length}'),
                    style: TextStyle(color: palette.mutedText, fontSize: 12),
                  ),
                  if (course.displayed > Duration.zero) ...[
                    const SizedBox(width: 14),
                    Icon(Icons.schedule, size: 16, color: palette.mutedText),
                    const SizedBox(width: 5),
                    Text(
                      l10n
                          .d('Bekeken: {tijd}')
                          .replaceAll('{tijd}', _duration(course.displayed)),
                      style: TextStyle(color: palette.mutedText, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    l10n.d('Voortgang'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${(course.fraction * 100).round()}%',
                    style: TextStyle(color: palette.mutedText, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: course.fraction,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  semanticsLabel: l10n.d('Voortgang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(AppLocalizations l10n, ThemeData theme, _Course course) {
    final label = course.completed
        ? l10n.d('Afgerond')
        : course.started
        ? l10n.d('Bezig')
        : l10n.d('Nieuw');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: course.completed
            ? AppTheme.successBg
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: course.completed
              ? AppTheme.successFg
              : theme.colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _privacyNotice(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: palette.accentInk),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            l10n.d(
              'Tijdens het afspelen synchroniseert OciDeck de laatste dia, voltooiing en getoonde tijd per dia met deze organisatie. Dit is geen bewijs van aandacht of actieve leertijd.',
            ),
            style: TextStyle(fontSize: 11.5, color: palette.mutedText),
          ),
        ),
      ],
    ),
  );

  Widget _errorView(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
  ) => _emptyView(
    l10n,
    theme,
    palette,
    Icons.cloud_off_outlined,
    _error == 'no_organization'
        ? l10n.d('Uw account hoort niet bij een actieve organisatie.')
        : _error == 'too_many_lessons'
        ? l10n.d('Deze organisatie bevat te veel lessen om veilig te tonen.')
        : _error == 'package_failed'
        ? l10n.d('Kon dit bestand niet openen.')
        : l10n.d('De opleidingen konden niet worden opgehaald.'),
    action: OutlinedButton.icon(
      onPressed: _error == 'package_failed' && _failedLesson != null
          ? () => _open(_failedLesson!)
          : _load,
      icon: const Icon(Icons.refresh),
      label: Text(l10n.d('Opnieuw proberen')),
    ),
  );

  Widget _emptyView(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    IconData icon,
    String message, {
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: palette.mutedText),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    ),
  );

  List<_Course> _courses(AppLocalizations l10n) {
    final groups = <String, List<OciServeFeedItem>>{};
    for (final lesson in _lessons) {
      groups.putIfAbsent(lesson.versionId, () => []).add(lesson);
    }
    return [
      for (final entry in groups.entries)
        _Course.from(
          entry.key,
          entry.value,
          _progressByLesson,
          fallbackTitle: l10n.d('Opleiding'),
        ),
    ];
  }

  String? _preferredCourseVersion() {
    for (final lesson in _lessons) {
      final state = _stateFor(lesson);
      if (state?.lastSlideAnchor != null && state?.completed != true) {
        return lesson.versionId;
      }
    }
    for (final lesson in _lessons) {
      if (_stateFor(lesson)?.completed != true) return lesson.versionId;
    }
    return _lessons.firstOrNull?.versionId;
  }

  String _completedLabel(AppLocalizations l10n, _Course course) => l10n
      .d('{afgerond} van {totaal} lessen afgerond')
      .replaceAll('{afgerond}', '${course.done}')
      .replaceAll('{totaal}', '${course.lessons.length}');

  OciServeLessonState? _stateFor(OciServeFeedItem lesson) =>
      _progressByLesson[_progressKey(lesson.versionId, lesson.lessonId)];

  static String _progressKey(String versionId, String lessonId) =>
      '$versionId\u0000$lessonId';

  Future<void> _open(OciServeFeedItem lesson) async {
    final org = _organizationId;
    if (org == null) return;
    setState(() {
      _openingLessonId = lesson.lessonId;
      _failedLesson = null;
      _error = null;
    });
    try {
      final package = await ref
          .read(ociServeProvider.notifier)
          .lessonPackage(organizationId: org, lesson: lesson);
      // De gebruiker kan de dialoog sluiten terwijl de download nog loopt.
      // Open daarna niet alsnog buiten diens zicht een nieuw cursustabblad.
      if (!mounted) return;
      final result = await ref
          .read(tabsProvider.notifier)
          .openLearningPackage(
            package.bytes,
            '${lesson.title}.ocideck',
            LearningSessionRef(
              serverUrl: ref.read(ociServeProvider).settings.normalizedBaseUrl,
              accountId: ref.read(ociServeProvider).account!.id,
              organizationId: org,
              enrollmentId: lesson.enrollmentId,
              courseVersionId: lesson.versionId,
              lessonId: lesson.lessonId,
              packageHash: package.sha256,
              startedAt: DateTime.now().toUtc(),
            ),
            // Een afgeronde les opnieuw starten betekent echt opnieuw: het
            // laatst bewaarde anker is dan doorgaans juist de einddia.
            initialAnchor: _stateFor(lesson)?.completed == true
                ? null
                : _stateFor(lesson)?.lastSlideAnchor,
          );
      if (!mounted) return;
      if (result == OpenResult.opened) {
        Navigator.pop(context);
      } else {
        setState(() {
          _failedLesson = lesson;
          _error = 'package_failed';
        });
      }
    } catch (error, stack) {
      logError('OciServe: les openen', error.runtimeType, stack);
      if (mounted) {
        setState(() {
          _failedLesson = lesson;
          _error = 'package_failed';
        });
      }
    } finally {
      if (mounted) setState(() => _openingLessonId = null);
    }
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    return words
        .take(2)
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
  }

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _Course {
  const _Course({
    required this.versionId,
    required this.title,
    required this.lessons,
    required this.states,
  });

  final String versionId;
  final String title;
  final List<OciServeFeedItem> lessons;
  final Map<String, OciServeLessonState> states;

  factory _Course.from(
    String versionId,
    List<OciServeFeedItem> source,
    Map<String, OciServeLessonState> progressByLesson, {
    required String fallbackTitle,
  }) {
    final lessons = [...source]
      ..sort((a, b) => a.lessonOrder.compareTo(b.lessonOrder));
    return _Course(
      versionId: versionId,
      title: lessons.first.courseTitle.isEmpty
          ? fallbackTitle
          : lessons.first.courseTitle,
      lessons: lessons,
      states: {
        for (final lesson in lessons)
          lesson.lessonId:
              ?progressByLesson[_progressKey(versionId, lesson.lessonId)],
      },
    );
  }

  int get done => lessons
      .where((lesson) => states[lesson.lessonId]?.completed == true)
      .length;
  bool get completed => done == lessons.length;
  bool get started => lessons.any((lesson) => states[lesson.lessonId] != null);
  double get fraction => lessons.isEmpty ? 0 : done / lessons.length;
  Duration get displayed => Duration(
    milliseconds: states.values.fold(
      0,
      (total, state) => total + state.displayedMilliseconds,
    ),
  );
  OciServeFeedItem get nextLesson {
    if (completed) return lessons.first;
    return lessons.firstWhere(
      (lesson) {
        final state = states[lesson.lessonId];
        return state?.lastSlideAnchor != null && state?.completed != true;
      },
      orElse: () => lessons.firstWhere(
        (lesson) => states[lesson.lessonId]?.completed != true,
      ),
    );
  }

  static String _progressKey(String versionId, String lessonId) =>
      '$versionId\u0000$lessonId';
}
