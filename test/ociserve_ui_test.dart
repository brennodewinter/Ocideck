import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/playback.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/settings/ociserve_module_card.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

const _account = OciServeAccount(
  id: 'learner',
  displayName: 'Lerende',
  memberships: [
    OciServeMembership(organizationId: 'org', name: 'Opleidingsorganisatie'),
  ],
);

const _firstLesson = OciServeFeedItem(
  versionId: 'version',
  lessonId: 'one',
  title: 'Kennismaken',
  enrollmentId: 'enrollment',
  courseTitle: 'Veilig werken',
  lessonOrder: 1,
);

const _feed = [
  _firstLesson,
  OciServeFeedItem(
    versionId: 'version',
    lessonId: 'two',
    title: 'Praktijk',
    enrollmentId: 'enrollment',
    courseTitle: 'Veilig werken',
    lessonOrder: 2,
  ),
];

const _progress = OciServeLearningState([
  OciServeLessonState(
    courseVersionId: 'version',
    lessonId: 'one',
    completed: true,
    lastSlideAnchor: 'einde',
    displayedMilliseconds: 90000,
  ),
]);

class _FixedOciServeNotifier extends OciServeNotifier {
  _FixedOciServeNotifier(
    this.initial, {
    this.feed = _feed,
    this.progress = _progress,
    this.package,
  });

  final OciServeState initial;
  final List<OciServeFeedItem> feed;
  final OciServeLearningState progress;
  final OciServePackage? package;
  PlaybackReport? reportedPlayback;

  @override
  OciServeState build() => initial;

  @override
  Future<List<OciServeFeedItem>> learningFeed(String organizationId) async =>
      feed;

  @override
  Future<OciServeLearningState> learningState(String organizationId) async =>
      progress;

  @override
  Future<OciServePackage> lessonPackage({
    required String organizationId,
    required OciServeFeedItem lesson,
  }) async => package!;

  @override
  Future<void> reportPlayback({
    required LearningSessionRef session,
    required PlaybackReport report,
    required DateTime startedAt,
  }) async {
    reportedPlayback = report;
  }

  @override
  Future<void> flushPendingReports() async {}
}

Uint8List _lessonPackage() {
  const markdown = '''
---
marp: true
title: Cursusles
---
<!-- ocideck_slide_anchor: begin -->
# Begin

---

<!-- ocideck_slide_anchor: einde -->
# Einde
''';
  final archive = Archive()
    ..add(ArchiveFile.bytes('les.md', utf8.encode(markdown)));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _authenticated = OciServeState(
  settings: OciServeSettings(enabled: true),
  status: OciServeStatus.authenticated,
  account: _account,
);

_FixedOciServeNotifier _lessonNotifier({bool? completed}) =>
    _FixedOciServeNotifier(
      _authenticated,
      feed: const [_firstLesson],
      progress: completed == null
          ? const OciServeLearningState([])
          : OciServeLearningState([
              OciServeLessonState(
                courseVersionId: 'version',
                lessonId: 'one',
                completed: completed,
                lastSlideAnchor: 'einde',
                displayedMilliseconds: 90000,
              ),
            ]),
      package: OciServePackage(
        bytes: _lessonPackage(),
        sha256: 'test',
        playbackPolicy: 'play-only',
      ),
    );

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  _FixedOciServeNotifier notifier,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ociServeProvider.overrideWith(() => notifier)],
      child: const OciDeckApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

Future<void> _openCourses(WidgetTester tester) async {
  await tester.tap(find.text('Mijn cursussen'));
  await tester.pumpAndSettle();
}

Future<void> _actUntil(
  WidgetTester tester,
  Future<void> Function() action,
  bool Function() done,
  String reason,
) async {
  await tester.runAsync(action);
  await pumpUntil(tester, done, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  testWidgets('de OciServe-instellingen tonen uitleg en veilige foutstatus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ociServeProvider.overrideWith(
            () => _FixedOciServeNotifier(
              const OciServeState(
                settings: OciServeSettings(enabled: true),
                status: OciServeStatus.signedOut,
                errorCode: 'invalid_url',
                warningCode: 'pending_reports_preserved',
                identityProviderHost: 'aanmelden.example.org',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(body: OciServeModuleCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OciServe-server'), findsOneWidget);
    expect(find.text('Ingelogd blijven op dit apparaat'), findsOneWidget);
    expect(find.text('Vertrouwde interne server'), findsOneWidget);
    expect(find.text('Vul een geldig OciServe-adres in.'), findsOneWidget);
    expect(find.text('Inloggen'), findsOneWidget);
    expect(find.textContaining('aanmelden.example.org'), findsOneWidget);
    expect(
      find.text('Nog niet verstuurde voortgang is op dit apparaat bewaard.'),
      findsOneWidget,
    );
  });

  testWidgets('Mijn cursussen blijft verborgen zonder geldige aanmelding', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        const OciServeState(
          settings: OciServeSettings(enabled: true),
          status: OciServeStatus.signedOut,
          errorCode: 'restore_failed',
        ),
      ),
    );

    expect(find.text('Mijn cursussen'), findsNothing);
    expect(
      find.textContaining('Aanmelden bij OciServe is niet gelukt'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Mijn cursussen toont dashboard en wisselt de uitgelichte cursus',
    (tester) async {
      await _pumpApp(
        tester,
        _FixedOciServeNotifier(
          _authenticated,
          feed: const [
            ..._feed,
            OciServeFeedItem(
              versionId: 'privacy',
              lessonId: 'privacy-one',
              title: 'Persoonsgegevens',
              enrollmentId: 'privacy-enrollment',
              courseTitle: 'Privacybasis',
              lessonOrder: 1,
            ),
          ],
        ),
      );

      expect(find.text('Mijn cursussen'), findsOneWidget);
      await _openCourses(tester);

      final hero = find.byKey(const Key('ociserve-featured-course'));
      expect(hero, findsOneWidget);
      expect(
        find.descendant(of: hero, matching: find.text('Veilig werken')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Nu bezig')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Verdergaan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('50%')),
        findsOneWidget,
      );
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Bezig')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Nieuw')),
        findsOneWidget,
      );
      expect(find.text('Bekeken: 1:30'), findsOneWidget);
      expect(find.text('2 cursussen'), findsOneWidget);

      final heroContainer = tester.widget<Container>(hero);
      final theme = Theme.of(tester.element(hero));
      expect(
        (heroContainer.decoration! as BoxDecoration).color,
        AppPalette.of(theme).panel,
        reason: 'het uitgelichte vlak hoort de actieve themapaletten te volgen',
      );

      await tester.tap(find.text('Privacybasis'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: hero, matching: find.text('Privacybasis')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Klaar om te beginnen')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Starten')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('0%')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Verdergaan opent de volgende les op het bewaarde anker', (
    tester,
  ) async {
    final container = await _pumpApp(tester, _lessonNotifier(completed: false));

    await _openCourses(tester);
    await tester.tap(find.text('Verdergaan'));
    await tester.pumpAndSettle();

    final tab = container.read(tabsProvider).current!;
    expect(tab.learningSession?.lessonId, 'one');
    expect(tab.editorNotifier.currentState.selectedIndex, 1);
    expect(tab.deckNotifier.currentState.deck?.slides[1].title, 'Einde');
  });

  testWidgets('afgeronde cursus start opnieuw zonder oud eindanker', (
    tester,
  ) async {
    final container = await _pumpApp(tester, _lessonNotifier(completed: true));

    await _openCourses(tester);
    final hero = find.byKey(const Key('ociserve-featured-course'));
    expect(
      find.descendant(of: hero, matching: find.text('Afgerond')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.text('U kunt deze cursus opnieuw bekijken.'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Opnieuw starten'));
    await tester.pumpAndSettle();

    final tab = container.read(tabsProvider).current!;
    expect(tab.learningSession?.lessonId, 'one');
    expect(tab.editorNotifier.currentState.selectedIndex, 0);
    expect(tab.deckNotifier.currentState.deck?.slides.first.title, 'Begin');
  });

  testWidgets('voltooide les toont na playback het afrondscherm', (
    tester,
  ) async {
    final notifier = _lessonNotifier();
    final container = await _pumpApp(tester, notifier);
    await _openCourses(tester);
    await tester.tap(find.text('Starten'));
    await tester.pumpAndSettle();

    await _actUntil(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Afspelen')),
      () => find.byType(FullscreenPresenter).evaluate().isNotEmpty,
      'de lespresentatie kwam niet op',
    );
    await _actUntil(
      tester,
      () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      },
      () => find.text('Les afgerond').evaluate().isNotEmpty,
      'het afrondscherm verscheen niet',
    );

    expect(notifier.reportedPlayback?.completed, isTrue);
    expect(find.text('Mooi gedaan! Uw voortgang is bewaard.'), findsOneWidget);
    expect(find.text('Doorgaan in de les'), findsOneWidget);
    expect(find.text('Terug naar mijn cursussen'), findsOneWidget);

    await _actUntil(
      tester,
      () => tester.tap(find.text('Terug naar mijn cursussen')),
      () => find
          .byKey(const Key('ociserve-featured-course'))
          .evaluate()
          .isNotEmpty,
      'het cursusoverzicht verscheen niet opnieuw',
    );

    expect(container.read(tabsProvider).current?.isOpen, isFalse);
    expect(find.byKey(const Key('ociserve-featured-course')), findsOneWidget);
  });
}
