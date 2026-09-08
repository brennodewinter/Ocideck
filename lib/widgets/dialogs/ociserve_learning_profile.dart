import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_models.dart';
import '../../theme/app_theme.dart';
import 'ociserve_account_avatar.dart';
import 'ociserve_course_summary.dart';

class OciServeLearningProfile extends StatelessWidget {
  const OciServeLearningProfile({
    super.key,
    required this.account,
    required this.courses,
    required this.onOpenCourse,
  });

  final OciServeAccount account;
  final List<OciServeCourseSummary> courses;
  final ValueChanged<String> onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final l10n = context.l10n;
    final lessons = courses.expand((course) => course.lessons).toList();
    final states = courses.expand((course) => course.states.values).toList();
    final completedCourses = courses.where((course) => course.completed).length;
    final completedLessons = states.where((state) => state.completed).length;
    final displayed = Duration(
      milliseconds: states.fold(
        0,
        (total, state) => total + state.displayedMilliseconds,
      ),
    );
    final latest = states
        .map((state) => state.lastPlayedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return CustomScrollView(
      key: const Key('ociserve-learning-profile'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          sliver: SliverList.list(
            children: [
              _hero(context, completedCourses),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < 620
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric(
                        context,
                        width,
                        Icons.workspace_premium_outlined,
                        l10n
                            .d('{afgerond} van {totaal}')
                            .replaceAll('{afgerond}', '$completedCourses')
                            .replaceAll('{totaal}', '${courses.length}'),
                        l10n.d('Cursussen afgerond'),
                      ),
                      _metric(
                        context,
                        width,
                        Icons.task_alt,
                        l10n
                            .d('{afgerond} van {totaal}')
                            .replaceAll('{afgerond}', '$completedLessons')
                            .replaceAll('{totaal}', '${lessons.length}'),
                        l10n.d('Lessen afgerond'),
                      ),
                      _metric(
                        context,
                        width,
                        Icons.schedule,
                        _duration(context, displayed),
                        l10n.d('Tijd in beeld'),
                      ),
                      _metric(
                        context,
                        width,
                        Icons.history,
                        latest == null
                            ? l10n.d('Nog niet gestart')
                            : MaterialLocalizations.of(
                                context,
                              ).formatCompactDate(latest.toLocal()),
                        l10n.d('Laatste activiteit'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle(
                theme,
                l10n.d('Voortgang per cursus'),
                l10n.d('Een volledig overzicht van uw afgeronde lessen.'),
              ),
              const SizedBox(height: 12),
              _chart(context),
              const SizedBox(height: 24),
              _sectionTitle(
                theme,
                l10n.d('Recente activiteit'),
                l10n.d('Uw laatst bekeken lessen, meest recent bovenaan.'),
              ),
              const SizedBox(height: 12),
              _recentActivity(context),
              const SizedBox(height: 24),
              _sectionTitle(
                theme,
                l10n.d('Uw cursussen'),
                l10n.d('Alle lessen, voortgang en bekeken tijd bij elkaar.'),
              ),
              const SizedBox(height: 12),
              for (final course in courses) ...[
                _course(context, course),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: palette.accentInk,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        l10n.d(
                          'Bekeken tijd betekent dat een dia in beeld stond. Het is geen meting van aandacht of actieve studietijd.',
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero(BuildContext context, int completedCourses) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final l10n = context.l10n;
    final name = account.displayName.trim().isEmpty
        ? l10n.d('Cursist')
        : account.displayName;
    final fraction = courses.isEmpty ? 0.0 : completedCourses / courses.length;
    return Container(
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final progress = Semantics(
            label: l10n
                .d('{percentage}% van de cursussen afgerond')
                .replaceAll('{percentage}', '${(fraction * 100).round()}'),
            child: SizedBox.square(
              dimension: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 8,
                    backgroundColor: palette.panelText.withValues(alpha: 0.18),
                    color: theme.colorScheme.secondary,
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: TextStyle(
                      color: palette.panelText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
          final identity = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OciServeAccountAvatar(account: account, name: name, size: 72),
              const SizedBox(width: 18),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: palette.panelText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.d('Uw persoonlijke leerresultaten'),
                      style: TextStyle(
                        color: palette.panelText.withValues(alpha: 0.76),
                      ),
                    ),
                    if (account.email.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${l10n.d('E-mail')}: ${account.email}',
                        style: TextStyle(color: palette.panelText),
                      ),
                    ],
                    if (account.activeMemberships.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.d('Organisaties')}: ${account.activeMemberships.map((membership) => membership.name).where((name) => name.isNotEmpty).join(', ')}',
                        style: TextStyle(color: palette.panelText),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 18), progress],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              progress,
            ],
          );
        },
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    double width,
    IconData icon,
    String value,
    String label,
  ) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    return Container(
      width: width,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(label, style: TextStyle(color: palette.mutedText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final shown = courses.take(8).toList();
    final description = shown
        .map((course) => '${course.title}: ${(course.fraction * 100).round()}%')
        .join(', ');
    return Semantics(
      label: '${context.l10n.d('Voortgang per cursus')}: $description',
      child: Container(
        height: 230,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: 100,
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(enabled: false),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (_) => FlLine(
                color: theme.colorScheme.outlineVariant,
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: 25,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.round()}%',
                    style: TextStyle(fontSize: 10, color: palette.mutedText),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= shown.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.mutedText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < shown.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: shown[i].fraction * 100,
                      width: 24,
                      color: shown[i].completed
                          ? AppTheme.successFg
                          : theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 450),
        ),
      ),
    );
  }

  Widget _recentActivity(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final recent = <({OciServeFeedItem lesson, OciServeLessonState state})>[];
    for (final course in courses) {
      for (final lesson in course.lessons) {
        final state = course.states[lesson.lessonId];
        if (state?.lastPlayedAt != null) {
          recent.add((lesson: lesson, state: state!));
        }
      }
    }
    recent.sort(
      (a, b) => b.state.lastPlayedAt!.compareTo(a.state.lastPlayedAt!),
    );
    if (recent.isEmpty) {
      return _emptyCard(context, context.l10n.d('Nog geen lessen bekeken.'));
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < recent.take(5).length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: recent[i].state.completed
                    ? AppTheme.successBg
                    : theme.colorScheme.primaryContainer,
                foregroundColor: recent[i].state.completed
                    ? AppTheme.successFg
                    : theme.colorScheme.onPrimaryContainer,
                child: Icon(
                  recent[i].state.completed ? Icons.check : Icons.play_arrow,
                ),
              ),
              title: Text(recent[i].lesson.title),
              subtitle: Text(
                '${recent[i].lesson.courseTitle} · ${_duration(context, Duration(milliseconds: recent[i].state.displayedMilliseconds))}',
                style: TextStyle(color: palette.mutedText),
              ),
              trailing: Text(
                MaterialLocalizations.of(
                  context,
                ).formatCompactDate(recent[i].state.lastPlayedAt!.toLocal()),
                style: TextStyle(color: palette.mutedText, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _course(BuildContext context, OciServeCourseSummary course) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme);
    final l10n = context.l10n;
    return Card(
      key: Key('learning-profile-course-${course.versionId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpenCourse(course.versionId),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      course.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _status(context, course),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: course.fraction,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      semanticsLabel: l10n.d('Voortgang'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(course.fraction * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l10n
                    .d('{afgerond} van {totaal} lessen afgerond')
                    .replaceAll('{afgerond}', '${course.done}')
                    .replaceAll('{totaal}', '${course.lessons.length}'),
                style: TextStyle(color: palette.mutedText),
              ),
              const SizedBox(height: 12),
              for (final lesson in course.lessons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        course.states[lesson.lessonId]?.completed == true
                            ? Icons.check_circle
                            : course.states[lesson.lessonId] != null
                            ? Icons.timelapse
                            : Icons.circle_outlined,
                        size: 17,
                        color: course.states[lesson.lessonId]?.completed == true
                            ? AppTheme.successFg
                            : palette.mutedText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(lesson.title)),
                      Text(
                        _duration(
                          context,
                          Duration(
                            milliseconds:
                                course
                                    .states[lesson.lessonId]
                                    ?.displayedMilliseconds ??
                                0,
                          ),
                        ),
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context, OciServeCourseSummary course) {
    final theme = Theme.of(context);
    final label = course.completed
        ? context.l10n.d('Afgerond')
        : course.started
        ? context.l10n.d('Bezig')
        : context.l10n.d('Nieuw');
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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(text, textAlign: TextAlign.center),
  );

  Widget _sectionTitle(ThemeData theme, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(color: AppPalette.of(theme).mutedText),
          ),
        ],
      );

  static String _duration(BuildContext context, Duration duration) {
    if (duration <= Duration.zero) return '0:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return context.l10n
          .d('{uren} u {minuten} min')
          .replaceAll('{uren}', '$hours')
          .replaceAll('{minuten}', minutes.toString().padLeft(2, '0'));
    }
    return '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }
}
