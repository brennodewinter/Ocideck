part of '../ociserve_courses_dialog.dart';

/// De cursussectie van de leeromgeving-dialoog: uitgelichte cursus, kaarten
/// en statuschips. Apart part-bestand om de dialoog onder de bestandsgrens
/// te houden, naast de privacy- en bewijssecties.
extension _OciServeCoursesDialogCourses on _OciServeCoursesDialogState {
  Widget _featuredCourse(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeCourseSummary course,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          ? '${l10n.d('Les')} ${course.nextLessonNumber} / ${course.lessons.length} · ${next.title}'
                          : '${l10n.d('Volgende: {les}').replaceAll('{les}', next.title)} · ${l10n.d('Les')} 1 / ${course.lessons.length}',
                      style: TextStyle(
                        color: palette.panelText.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              if (course.imageHash.isNotEmpty) ...[
                const SizedBox(width: 18),
                _courseArtwork(
                  theme,
                  course,
                  width: 160,
                  height: 90,
                  key: const Key('ociserve-featured-image'),
                ),
              ],
            ],
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
          _openCourseButton(l10n, theme, next, opening, buttonLabel),
        ],
      ),
    );
  }

  Widget _openCourseButton(
    AppLocalizations l10n,
    ThemeData theme,
    OciServeFeedItem next,
    bool opening,
    String buttonLabel,
  ) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: _openingLessonId == null ? () => _open(next) : null,
      icon: opening
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(opening ? l10n.d('Binnenhalen…') : buttonLabel),
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.secondary,
        foregroundColor: AppTheme.labelOn(theme.colorScheme.secondary),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );

  Widget _courseCard(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
    OciServeCourseSummary course,
  ) {
    final selected = course.versionId == _selectedCourseVersionId;
    return Semantics(
      button: true,
      selected: selected,
      label: '${course.title}. ${_completedLabel(l10n, course)}',
      child: InkWell(
        onTap: () => _selectCourse(course.versionId),
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
                  _courseArtwork(
                    theme,
                    course,
                    width: 74,
                    height: 48,
                    key: Key('ociserve-course-image-${course.versionId}'),
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
                          .replaceAll(
                            '{tijd}',
                            _OciServeCoursesDialogState._duration(
                              course.displayed,
                            ),
                          ),
                      style: TextStyle(color: palette.mutedText, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    course.completed
                        ? l10n.d('Voortgang')
                        : '${l10n.d('Les')} ${course.nextLessonNumber} / ${course.lessons.length}',
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

  Widget _statusChip(
    AppLocalizations l10n,
    ThemeData theme,
    OciServeCourseSummary course,
  ) {
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

  Widget _courseArtwork(
    ThemeData theme,
    OciServeCourseSummary course, {
    required double width,
    required double height,
    required Key key,
  }) {
    Widget fallback() => ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          course.completed
              ? Icons.workspace_premium_outlined
              : Icons.shield_outlined,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
    final org = _organizationId;
    if (org == null || course.imageHash.isEmpty) {
      return SizedBox(
        key: key,
        width: width,
        height: height,
        child: fallback(),
      );
    }
    final provider = CappedImage(
      'ociserve-course:${course.imageHash}',
      () => ref
          .read(ociServeProvider.notifier)
          .courseImage(organizationId: org, imageHash: course.imageHash),
    );
    return SizedBox(
      key: key,
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          semanticLabel: course.title,
          errorBuilder: (context, error, stack) {
            logWarning('OciServe: cursusafbeelding tonen mislukt', error);
            return fallback();
          },
        ),
      ),
    );
  }

  void _selectCourse(String versionId) {
    _mutate(() => _selectedCourseVersionId = versionId);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }
}
