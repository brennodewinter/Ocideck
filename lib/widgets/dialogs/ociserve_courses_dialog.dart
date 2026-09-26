import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_models.dart';
import '../../state/ociserve_provider.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_limits.dart';
import '../../utils/log.dart';
import '../connection_status.dart';
import 'ociserve_account_avatar.dart';
import 'ociserve_bookings_view.dart';
import 'ociserve_course_summary.dart';
import 'ociserve_courses_sidebar.dart';
import 'ociserve_data_access.dart';
import 'ociserve_evidence.dart';
import 'ociserve_exam_button.dart';
import 'ociserve_learning_profile.dart';
import 'ociserve_offerings_view.dart';

part 'parts/ociserve_courses_dialog_privacy.dart';
part 'parts/ociserve_courses_dialog_evidence.dart';
part 'parts/ociserve_courses_dialog_courses.dart';
part 'parts/ociserve_courses_dialog_status.dart';

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
  final _scrollController = ScrollController();

  String? _organizationId;
  bool _loading = true;
  String? _error;
  List<OciServeFeedItem> _lessons = const [];
  Map<String, OciServeLessonState> _progressByLesson = const {};
  String? _openingLessonId;
  OciServeFeedItem? _failedLesson;
  String? _selectedCourseVersionId;
  OciServeCoursesSection _section = OciServeCoursesSection.courses;
  bool _privacyLoading = false;
  String? _privacyError;
  OciServePrivacyData? _privacyData;
  bool _evidenceLoading = false;
  String? _evidenceError;
  List<EvidenceUpload> _evidenceUploads = const [];
  List<OciServeQualification> _qualifications = const [];

  void _mutate(VoidCallback change) => setState(change);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
      // De beschikbare hoogte komt uit de werkelijke layout-constraints, niet
      // uit MediaQuery: in tests wijkt die af van de echte surface.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : available.height - 40;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1040,
              // Een minimumhoogte houdt de zes zijbalkbestemmingen bereikbaar
              // ook wanneer de inhoud (laadspinner, lege lijst) de dialoog
              // anders tot een fractie van het venster zou laten krimpen.
              minHeight: maxHeight.clamp(0.0, 760.0),
              maxHeight: maxHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact)
                  OciServeCoursesSidebar(
                    account: account,
                    section: _section,
                    onSelect: _showSection,
                  ),
                Expanded(
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(theme, palette, memberships, compact),
                        Expanded(child: _body(context.l10n, theme, palette)),
                        _OciServeConnectionFooter(onReload: _load),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
          if (_section != OciServeCoursesSection.courses)
            IconButton(
              tooltip: l10n.d('Terug naar mijn cursussen'),
              onPressed: () => _showSection(OciServeCoursesSection.courses),
              icon: const Icon(Icons.arrow_back),
            )
          else if (compact) ...[
            Semantics(
              button: true,
              label: l10n.d('Bekijk mijn voortgang'),
              child: InkWell(
                key: const Key('ociserve-compact-profile-button'),
                onTap: () => _showSection(OciServeCoursesSection.progress),
                customBorder: const CircleBorder(),
                child: OciServeAccountAvatar(account: account, name: name),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _section.eyebrow(l10n),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.accentInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _section.title(l10n, name: name),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _section.subtitle(l10n),
                  style: TextStyle(color: palette.mutedText),
                ),
              ],
            ),
          ),
          if (memberships.length > 1 && !compact) ...[
            const SizedBox(width: 16),
            SizedBox(width: 210, child: _organizationPicker(memberships)),
          ],
          ...ociServeExamActions(_organizationId, compact),
          IconButton(
            tooltip: l10n.t('close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  void _showSection(OciServeCoursesSection section) {
    setState(() {
      _section = section;
      if (_error == 'package_failed') {
        _error = null;
        _failedLesson = null;
      }
    });
    if (section == OciServeCoursesSection.data &&
        _privacyData == null &&
        !_privacyLoading) {
      _loadPrivacyData();
    }
    if (section == OciServeCoursesSection.evidence &&
        _evidenceUploads.isEmpty &&
        !_evidenceLoading) {
      _loadEvidence();
    }
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
          _privacyData = null;
          _privacyError = null;
          _load();
          if (_section == OciServeCoursesSection.data) _loadPrivacyData();
        },
      );

  Widget _body(AppLocalizations l10n, ThemeData theme, AppPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_section == OciServeCoursesSection.data) {
      return _privacyBody(l10n, theme, palette);
    }
    if (_section == OciServeCoursesSection.evidence) {
      return _evidenceBody(l10n, theme, palette);
    }
    final org = _organizationId;
    if (_section == OciServeCoursesSection.bookings && org != null) {
      return OciServeBookingsView(organizationId: org);
    }
    if (_section == OciServeCoursesSection.offerings && org != null) {
      return OciServeOfferingsView(
        organizationId: org,
        onShowBookings: () => _showSection(OciServeCoursesSection.bookings),
      );
    }
    if (_error != null) return _errorView(l10n, theme, palette);
    final courses = _courses(l10n);
    if (_section == OciServeCoursesSection.progress) {
      return OciServeLearningProfile(
        account: ref.read(ociServeProvider).account!,
        courses: courses,
        onShowData: () => _showSection(OciServeCoursesSection.data),
        onOpenCourse: (versionId) {
          setState(() {
            _selectedCourseVersionId = versionId;
            _section = OciServeCoursesSection.courses;
          });
        },
      );
    }
    if (_lessons.isEmpty) {
      return _emptyView(
        l10n,
        theme,
        palette,
        Icons.school_outlined,
        l10n.d('Er staan geen opleidingen voor u klaar.'),
      );
    }
    final selected = courses.firstWhere(
      (course) => course.versionId == _selectedCourseVersionId,
      orElse: () => courses.first,
    );
    final oneColumn = MediaQuery.sizeOf(context).width < 760;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 12),
          sliver: SliverList.list(
            children: [
              if (ref.watch(ociServeProvider).memberships.length > 1 &&
                  oneColumn) ...[
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
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          sliver: SliverGrid.builder(
            itemCount: courses.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: oneColumn ? 1 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 200,
            ),
            itemBuilder: (context, index) =>
                _courseCard(l10n, theme, palette, courses[index]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 16, 30, 28),
          sliver: SliverToBoxAdapter(
            child: _privacyNotice(l10n, theme, palette),
          ),
        ),
      ],
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

  List<OciServeCourseSummary> _courses(AppLocalizations l10n) {
    final groups = <String, List<OciServeFeedItem>>{};
    for (final lesson in _lessons) {
      groups.putIfAbsent(lesson.versionId, () => []).add(lesson);
    }
    final selected = _selectedCourseVersionId;
    return <OciServeCourseSummary>[
      for (final entry in groups.entries)
        OciServeCourseSummary.from(
          entry.key,
          entry.value,
          _progressByLesson,
          fallbackTitle: l10n.d('Opleiding'),
        ),
    ]..sort((a, b) {
      if (a.versionId == selected) return -1;
      if (b.versionId == selected) return 1;
      return OciServeCourseSummary.compareForStudentOverview(a, b);
    });
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

  String _completedLabel(AppLocalizations l10n, OciServeCourseSummary course) =>
      l10n
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
      final opened = await ref
          .read(ociServeProvider.notifier)
          .openLessonPackage(
            organizationId: org,
            lesson: lesson,
            open: (bytes, password, packageProfile, session) async {
              // De gebruiker kan de dialoog sluiten terwijl de download loopt.
              // Open daarna niet alsnog buiten diens zicht een nieuw tabblad.
              if (!mounted) return false;
              final result = await openLearningPackage(
                ref.read(tabsProvider.notifier),
                bytes,
                '${lesson.title}.ocideck',
                session,
                password: password,
                packageProfile: packageProfile,
                // Een afgeronde les opnieuw starten betekent echt opnieuw:
                // het laatst bewaarde anker is dan juist de einddia.
                initialAnchor: _stateFor(lesson)?.completed == true
                    ? null
                    : _stateFor(lesson)?.lastSlideAnchor,
              );
              return result == OpenResult.opened;
            },
          );
      if (!mounted) return;
      if (opened) {
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

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
