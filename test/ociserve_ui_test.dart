import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_exam.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/playback.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/settings/ociserve_module_card.dart';
import 'package:ocideck/widgets/dialogs/settings/integrations_panel.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ociserve_aes_fixture.dart';
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
    this.loginSucceeds = true,
    this.courseImages = const {},
    int privacyFailures = 0,
    OciServePrivacyData? privacyData,
  }) : _privacyFailuresRemaining = privacyFailures,
       privacyDataValue =
           privacyData ??
           OciServePrivacyData(
             participantId: 'participant',
             generatedAt: DateTime.utc(2026, 9, 9),
             data: const {
               'participant': {'display_name': 'Lerende'},
             },
           );

  final OciServeState initial;
  final List<OciServeFeedItem> feed;
  final OciServeLearningState progress;
  final OciServePackage? package;
  final bool loginSucceeds;
  final Map<String, Uint8List> courseImages;
  final OciServePrivacyData privacyDataValue;
  int _privacyFailuresRemaining;
  int privacyDataCalls = 0;
  Uint8List? accountAvatarBytes;
  PlaybackReport? reportedPlayback;
  bool loginCalled = false;
  int examCurrentCalls = 0;

  @override
  OciServeState build() => initial;

  @override
  Future<List<OciServeFeedItem>> learningFeed(String organizationId) async =>
      feed;

  @override
  Future<OciServeLearningState> learningState(String organizationId) async =>
      progress;

  @override
  Future<OciServePrivacyData> privacyData(String organizationId) async {
    privacyDataCalls++;
    if (_privacyFailuresRemaining > 0) {
      _privacyFailuresRemaining--;
      throw StateError('test failure');
    }
    return privacyDataValue;
  }

  @override
  Future<bool> openLessonPackage({
    required String organizationId,
    required OciServeFeedItem lesson,
    required Future<bool> Function(
      Uint8List bytes,
      String password,
      String packageProfile,
      LearningSessionRef session,
    )
    open,
  }) async => open(
    package!.bytes,
    testOciServePackagePassword,
    package!.packageProfile,
    LearningSessionRef(
      serverUrl: initial.settings.normalizedBaseUrl,
      accountId: initial.account!.id,
      organizationId: organizationId,
      enrollmentId: lesson.enrollmentId,
      courseVersionId: lesson.versionId,
      lessonId: lesson.lessonId,
      playbackSessionId: 'lesson-session',
      packageHash: package!.sha256,
      startedAt: DateTime.utc(2026, 9, 12),
      expiresAt: DateTime.utc(2099),
    ),
  );

  @override
  Future<void> closeLessonSession(LearningSessionRef session) async {}

  @override
  Future<OciServeExamSessionList> examSessions(String organizationId) async =>
      OciServeExamSessionList(
        sessions: const [
          OciServeExamSession(id: 'exam-session', status: 'released'),
        ],
        serverTime: DateTime.utc(2026, 9, 12),
      );

  @override
  Future<OciServeExamAttempt> startExamAttempt({
    required String organizationId,
    required String sessionId,
    required String idempotencyKey,
  }) async => OciServeExamAttempt(
    id: 'attempt',
    participantId: 'participant',
    blueprintVersionId: 'blueprint',
    status: 'in_progress',
    startedAt: DateTime.utc(2026, 9, 12),
  );

  @override
  Future<OciServeCurrentExamItem?> currentExamItem({
    required String organizationId,
    required String attemptId,
  }) async {
    examCurrentCalls++;
    if (examCurrentCalls > 1) return null;
    return OciServeCurrentExamItem(
      attemptId: attemptId,
      attemptItemId: 'item',
      position: 0,
      question: 'Welke letter?',
      options: const [
        OciServeExamOption(id: 'a', text: 'A'),
        OciServeExamOption(id: 'b', text: 'B'),
      ],
      revision: 0,
      challenge: 'AAAAAAAAAAAAAAAAAAAAAA',
      challengeExpiresAt: DateTime.utc(2099),
    );
  }

  @override
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required OciServeExamAnswerMutation mutation,
  }) async => OciServeAcceptedExamAnswer(
    attemptId: mutation.attemptId,
    attemptItemId: mutation.attemptItemId,
    revision: 1,
    acceptedAt: DateTime.utc(2026, 9, 12),
  );

  @override
  Future<OciServeExamAttempt> submitExamAttempt({
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  }) async => OciServeExamAttempt(
    id: attemptId,
    participantId: 'participant',
    blueprintVersionId: 'blueprint',
    status: 'submitted',
    startedAt: DateTime.utc(2026, 9, 12),
    submittedAt: DateTime.utc(2026, 9, 12, 1),
  );

  @override
  Future<Uint8List> courseImage({
    required String organizationId,
    required String imageHash,
  }) async => courseImages[imageHash]!;

  @override
  Future<Uint8List> accountAvatar(String avatarHash) async =>
      accountAvatarBytes!;

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

  @override
  Future<bool> login() async {
    loginCalled = true;
    if (!loginSucceeds) {
      state = const OciServeState(
        settings: OciServeSettings(enabled: true),
        status: OciServeStatus.signedOut,
        errorCode: 'login_failed',
      );
      return false;
    }
    state = const OciServeState(
      settings: OciServeSettings(enabled: true),
      status: OciServeStatus.authenticated,
      account: _account,
    );
    return true;
  }
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
  return ociServeAesPackage({'les.md': utf8.encode(markdown)});
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
        packageProfile: 'ocideck-winzip-aes256-ae2-v1',
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

Future<Finder> _scrollToDataCategory(
  WidgetTester tester,
  String sourceKey,
) async {
  final finder = find.byKey(Key('data-category-$sourceKey'));
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('ociserve-data-access')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  return finder;
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
    FlutterSecureStorage.setMockInitialValues({});
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
          home: const Scaffold(body: OciServeIntegrationBody()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('eLearning-server'), findsOneWidget);
    expect(find.text('Ingelogd blijven op dit apparaat'), findsOneWidget);
    expect(find.text('Vertrouwde interne server'), findsOneWidget);
    expect(find.text('Vul een geldig eLearning-adres in.'), findsOneWidget);
    expect(find.text('Inloggen'), findsOneWidget);
    expect(find.textContaining('aanmelden.example.org'), findsOneWidget);
    expect(
      find.text('Nog niet verstuurde voortgang is op dit apparaat bewaard.'),
      findsOneWidget,
    );
  });

  testWidgets('eLearning-configuratie staat alleen onder Integraties', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ociServeProvider.overrideWith(
            () => _FixedOciServeNotifier(
              const OciServeState(status: OciServeStatus.signedOut),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.modules,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(OciServeIntegrationBody), findsNothing);
    final integrationsTab = find.text('Integraties');
    await tester.ensureVisible(integrationsTab);
    await tester.pumpAndSettle();
    await tester.tap(integrationsTab);
    await tester.pumpAndSettle();

    expect(find.text('eLearning'), findsWidgets);
    expect(find.text('OciServe'), findsNothing);
    expect(find.byType(OciServeIntegrationBody), findsNothing);

    final eLearningCard = find.ancestor(
      of: find.descendant(
        of: find.byType(IntegrationsPanel),
        matching: find.text('eLearning'),
      ),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(eLearningCard);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: eLearningCard, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OciServeIntegrationBody), findsOneWidget);
    expect(find.text('eLearning-server'), findsOneWidget);
  });

  testWidgets('eLearning blijft tijdens het laden niet schakelbaar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openKatAvailableProvider.overrideWithValue(false),
          ociServeProvider.overrideWith(
            () => _FixedOciServeNotifier(const OciServeState()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: IntegrationsPanel()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Alles inschakelen'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('welkomstscherm meldt aan en opent daarna Mijn cursussen', (
    tester,
  ) async {
    final notifier = _FixedOciServeNotifier(
      const OciServeState(
        settings: OciServeSettings(enabled: true),
        status: OciServeStatus.signedOut,
        errorCode: 'restore_failed',
      ),
    );
    await _pumpApp(tester, notifier);

    expect(find.text('Inloggen'), findsOneWidget);
    expect(
      find.textContaining('Aanmelden bij eLearning is niet gelukt'),
      findsOneWidget,
    );
    await tester.tap(find.text('Inloggen'));
    await tester.pumpAndSettle();
    expect(notifier.loginCalled, isTrue);
    expect(find.text('Mijn leeromgeving'), findsOneWidget);
  });

  testWidgets('mislukte login houdt een concrete herstelactie zichtbaar', (
    tester,
  ) async {
    final notifier = _FixedOciServeNotifier(
      const OciServeState(
        settings: OciServeSettings(enabled: true),
        status: OciServeStatus.signedOut,
      ),
      loginSucceeds: false,
    );
    await _pumpApp(tester, notifier);

    await tester.tap(find.text('Inloggen'));
    await tester.pumpAndSettle();

    expect(notifier.loginCalled, isTrue);
    expect(find.text('Inloggen'), findsOneWidget);
    expect(
      find.textContaining('Controleer de server en probeer opnieuw'),
      findsOneWidget,
    );
    expect(find.text('Mijn leeromgeving'), findsNothing);
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
      expect(find.text('Les 2 / 2 · Praktijk'), findsOneWidget);
      expect(find.text('2 cursussen'), findsOneWidget);

      final heroContainer = tester.widget<Container>(hero);
      final theme = Theme.of(tester.element(hero));
      expect(
        (heroContainer.decoration! as BoxDecoration).color,
        AppPalette.of(theme).panel,
        reason: 'het uitgelichte vlak hoort de actieve themapaletten te volgen',
      );

      await tester.ensureVisible(find.text('Privacybasis'));
      await tester.pumpAndSettle();
      final courseScroll = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(courseScroll).position.pixels,
        greaterThan(0),
      );
      await tester.tap(find.text('Privacybasis'));
      await tester.pumpAndSettle();

      expect(tester.state<ScrollableState>(courseScroll).position.pixels, 0);

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

  testWidgets('Mijn cursussen zet de actuele cursus altijd links vooraan', (
    tester,
  ) async {
    const feed = [
      OciServeFeedItem(
        versionId: 'done',
        lessonId: 'lesson',
        title: 'Les',
        courseTitle: 'Afgerond',
      ),
      OciServeFeedItem(
        versionId: 'new',
        lessonId: 'lesson',
        title: 'Les',
        courseTitle: 'Nieuw',
      ),
      OciServeFeedItem(
        versionId: 'active-z',
        lessonId: 'lesson',
        title: 'Les',
        courseTitle: 'Zakelijk mailen',
      ),
      OciServeFeedItem(
        versionId: 'active-a',
        lessonId: 'lesson',
        title: 'Les',
        courseTitle: 'Authenticatie',
      ),
    ];
    const progress = OciServeLearningState([
      OciServeLessonState(
        courseVersionId: 'done',
        lessonId: 'lesson',
        completed: true,
        displayedMilliseconds: 1,
      ),
      OciServeLessonState(
        courseVersionId: 'active-z',
        lessonId: 'lesson',
        completed: false,
        lastSlideAnchor: 'hervatten',
        displayedMilliseconds: 1,
      ),
      OciServeLessonState(
        courseVersionId: 'active-a',
        lessonId: 'lesson',
        completed: false,
        displayedMilliseconds: 1,
      ),
    ]);
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(_authenticated, feed: feed, progress: progress),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    await tester.pumpAndSettle();
    await _openCourses(tester);

    Offset position(String versionId) =>
        tester.getTopLeft(find.byKey(Key('ociserve-course-image-$versionId')));

    final activeA = position('active-a');
    final activeZ = position('active-z');
    expect(activeA.dy, closeTo(activeZ.dy, 1));
    expect(activeZ.dx, lessThan(activeA.dx));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();

    final fresh = position('new');
    final done = position('done');
    expect(fresh.dy, closeTo(done.dy, 1));
    expect(fresh.dx, lessThan(done.dx));
  });

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
    expect(find.text('Dia 2 / 2'), findsOneWidget);
  });

  testWidgets('Mijn cursussen toont de juiste cursusafbeelding', (
    tester,
  ) async {
    const hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlOQAAAAASUVORK5CYII=',
      ),
    );
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        feed: const [
          OciServeFeedItem(
            versionId: 'pictured',
            lessonId: 'one',
            title: 'Kennismaken',
            courseTitle: 'Cursus met beeld',
            courseImageHash: hash,
          ),
        ],
        progress: const OciServeLearningState([]),
        courseImages: {hash: png},
      ),
    );

    await _openCourses(tester);

    expect(find.byKey(const Key('ociserve-featured-image')), findsOneWidget);
    expect(
      find.byKey(const Key('ociserve-course-image-pictured')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('ociserve-featured-image')),
        matching: find.byIcon(Icons.shield_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('Mijn cursussen toont de profielfoto van het account', (
    tester,
  ) async {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlOQAAAAASUVORK5CYII=',
      ),
    );
    final notifier = _FixedOciServeNotifier(
      const OciServeState(
        settings: OciServeSettings(enabled: true),
        status: OciServeStatus.authenticated,
        account: OciServeAccount(
          id: 'learner',
          displayName: 'Lerende',
          avatarHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          memberships: [
            OciServeMembership(organizationId: 'org', name: 'Organisatie'),
          ],
        ),
      ),
    )..accountAvatarBytes = png;
    await _pumpApp(tester, notifier);
    await _openCourses(tester);

    expect(find.byKey(const Key('ociserve-account-avatar')), findsOneWidget);
  });

  testWidgets('de cursist opent een rijk persoonlijk voortgangsoverzicht', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        OciServeState(
          settings: const OciServeSettings(enabled: true),
          status: OciServeStatus.authenticated,
          account: OciServeAccount.fromJson(const {
            'account': {
              'id': 'learner',
              'display_name': 'Lerende',
              'email': 'lerende@example.nl',
            },
            'memberships': [
              {'organization_id': 'org', 'organization_name': 'Organisatie'},
            ],
          }),
        ),
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
        progress: OciServeLearningState([
          OciServeLessonState(
            courseVersionId: 'version',
            lessonId: 'one',
            completed: true,
            displayedMilliseconds: 90000,
            lastPlayedAt: DateTime.utc(2026, 9, 6),
          ),
          OciServeLessonState(
            courseVersionId: 'version',
            lessonId: 'two',
            completed: true,
            displayedMilliseconds: 120000,
            lastPlayedAt: DateTime.utc(2026, 9, 7),
          ),
        ]),
      ),
    );
    await _openCourses(tester);

    await tester.tap(find.text('Lerende'));
    await tester.pumpAndSettle();

    expect(find.text('Mijn voortgang'), findsWidgets);
    expect(find.textContaining('lerende@example.nl'), findsOneWidget);
    expect(find.textContaining('Organisatie'), findsOneWidget);
    expect(find.text('1 van 2'), findsOneWidget);
    expect(find.text('Cursussen afgerond'), findsOneWidget);
    expect(find.text('2 van 3'), findsOneWidget);
    expect(find.text('Lessen afgerond'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recente activiteit'),
      260,
      scrollable: find.descendant(
        of: find.byKey(const Key('ociserve-learning-profile')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Recente activiteit'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('learning-profile-course-version')),
      260,
      scrollable: find.descendant(
        of: find.byKey(const Key('ociserve-learning-profile')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const Key('learning-profile-course-version')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('learning-profile-course-privacy')),
      260,
      scrollable: find.descendant(
        of: find.byKey(const Key('ociserve-learning-profile')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const Key('learning-profile-course-privacy')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('learning-profile-course-privacy')));
    await tester.pumpAndSettle();

    expect(find.text('Cursussen voor u'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('ociserve-featured-course')),
        matching: find.text('Privacybasis'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Mijn voortgang houdt geen mislukte pakketfout vast', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        package: OciServePackage(
          bytes: Uint8List(0),
          sha256: '',
          playbackPolicy: 'play-only',
          packageProfile: 'ocideck-winzip-aes256-ae2-v1',
        ),
      ),
    );
    await _openCourses(tester);
    await tester.tap(find.text('Verdergaan'));
    await tester.pumpAndSettle();

    expect(find.text('Kon dit bestand niet openen.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ociserve-learning-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('Kon dit bestand niet openen.'), findsNothing);
    expect(find.byKey(const Key('ociserve-learning-profile')), findsOneWidget);
  });

  testWidgets('Mijn gegevens toont ook lege en onbekende servercategorieën', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        privacyData: OciServePrivacyData(
          participantId: 'participant-privacy',
          generatedAt: DateTime.utc(2026, 9, 9),
          data: const {
            'participant': {
              'display_name': 'Lerende',
              'future_field': 'blijft zichtbaar',
            },
            'future_category': [],
          },
        ),
      ),
    );
    await _openCourses(tester);

    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ociserve-data-access')), findsOneWidget);
    expect(find.text('Uw geregistreerde gegevens'), findsOneWidget);
    await _scrollToDataCategory(tester, 'future_category');
    expect(find.text('Future category'), findsOneWidget);
    expect(find.text('Geen gegevens geregistreerd'), findsOneWidget);

    await tester.tap(await _scrollToDataCategory(tester, 'participant'));
    await tester.pumpAndSettle();
    expect(find.text('blijft zichtbaar'), findsOneWidget);
    expect(find.textContaining('future_field'), findsOneWidget);
  });

  testWidgets('Mijn gegevens herstelt van een laadfout', (tester) async {
    final notifier = _FixedOciServeNotifier(_authenticated, privacyFailures: 1);
    await _pumpApp(tester, notifier);
    await _openCourses(tester);

    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();
    expect(
      find.text('Kon uw gegevens niet laden. Probeer het opnieuw.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Opnieuw proberen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ociserve-data-access')), findsOneWidget);
    expect(notifier.privacyDataCalls, 2);
  });

  testWidgets('Mijn gegevens maakt het inzagespoor begrijpelijk', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        privacyData: OciServePrivacyData(
          participantId: 'participant-audit',
          generatedAt: DateTime.utc(2026, 9, 9),
          data: const {
            'participant_data_access_history_metadata': {
              'available_from': '2026-09-01T08:30:00Z',
              'earlier_history': 'not_available',
            },
            'participant_data_access_history': [
              {
                'time': '2026-09-09T10:15:00Z',
                'retain_until': '2027-09-09T10:15:00Z',
                'operation': 'viewed',
                'data_category': 'learning_statistics',
                'purpose': 'assessment_and_certification',
                'actor_type': 'staff',
                'actor_role': 'assessor',
              },
            ],
          },
        ),
      ),
    );
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();

    await _scrollToDataCategory(
      tester,
      'participant_data_access_history_metadata',
    );
    expect(find.text('Beschikbaarheid van het inzagespoor'), findsOneWidget);
    await _scrollToDataCategory(tester, 'participant_data_access_history');
    expect(find.text('Inzage en wijzigingen'), findsOneWidget);
    await tester.tap(
      await _scrollToDataCategory(tester, 'participant_data_access_history'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bekeken'), findsOneWidget);
    expect(find.text('Leerstatistieken'), findsOneWidget);
    expect(find.text('Beoordeling en certificering'), findsOneWidget);
    expect(find.text('Medewerker'), findsOneWidget);
    expect(find.text('Beoordelaar'), findsOneWidget);
    expect(find.textContaining('actor_account_id'), findsNothing);
    expect(find.textContaining('request_id'), findsNothing);
  });

  testWidgets('Mijn gegevens zoekt lokaal door labels en waarden', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        privacyData: OciServePrivacyData(
          participantId: 'participant-search',
          generatedAt: DateTime.utc(2026, 9, 9),
          data: const {
            'participant': {
              'display_name': 'Ada Lovelace',
              'email': 'ada@example.test',
            },
            'lesson_progress': [
              {'lesson_id': 'les-over-privacy', 'completed': true},
            ],
            'enrollments': [
              {'status': 'active'},
            ],
          },
        ),
      ),
    );
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('privacy-data-search')),
      'Lovelace',
    );
    await tester.pumpAndSettle();

    await _scrollToDataCategory(tester, 'participant');
    expect(find.byKey(const Key('data-category-participant')), findsOneWidget);
    expect(
      find.byKey(const Key('data-category-lesson_progress')),
      findsNothing,
    );
    expect(find.text('1 categorie gevonden'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);

    await tester.tap(find.byKey(const Key('privacy-data-search-clear')));
    await tester.pumpAndSettle();
    await _scrollToDataCategory(tester, 'lesson_progress');
    expect(
      find.byKey(const Key('data-category-lesson_progress')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('privacy-data-search')),
      'Actief',
    );
    await tester.pumpAndSettle();
    await _scrollToDataCategory(tester, 'enrollments');
    final enrollmentCategory = find.byKey(
      const Key('data-category-enrollments'),
    );
    expect(enrollmentCategory, findsOneWidget);
    expect(
      find.descendant(of: enrollmentCategory, matching: find.text('Actief')),
      findsOneWidget,
    );
  });

  testWidgets('Mijn gegevens legt termen uit en toont geen JSON-blokken', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        privacyData: OciServePrivacyData(
          participantId: 'participant-readable',
          generatedAt: DateTime.utc(2026, 9, 9),
          data: const {
            'answers': [
              {
                'account_id': 'account-123',
                'answer_data': {
                  'selected_options': ['Eerste keuze', 'Tweede keuze'],
                  'confidence': 4,
                },
              },
            ],
          },
        ),
      ),
    );
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();

    expect(find.text('Antwoorden'), findsOneWidget);
    expect(
      find.text('De antwoorden die u bij toetsvragen heeft gegeven.'),
      findsOneWidget,
    );
    expect(find.text('Begrippen uitgelegd'), findsOneWidget);
    await tester.tap(find.text('Begrippen uitgelegd'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Een ID is een uniek technisch nummer'),
      findsOneWidget,
    );
    await tester.tap(find.text('Begrippen uitgelegd'));
    await tester.pumpAndSettle();

    await tester.tap(await _scrollToDataCategory(tester, 'answers'));
    await tester.pumpAndSettle();
    expect(find.text('Antwoordgegevens'), findsOneWidget);
    expect(find.text('Accountnummer'), findsOneWidget);
    expect(find.textContaining('account_id'), findsNothing);
    expect(find.text('Eerste keuze'), findsOneWidget);
    expect(find.text('Tweede keuze'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('['), findsNothing);
  });

  testWidgets('Mijn gegevens toont grote categorieën per vijftig', (
    tester,
  ) async {
    final records = List<Object?>.generate(
      51,
      (index) => {'marker': 'registratie-${index + 1}'},
    );
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        _authenticated,
        privacyData: OciServePrivacyData(
          participantId: 'participant-pagination',
          generatedAt: DateTime.utc(2026, 9, 9),
          data: {'large_category': records},
        ),
      ),
    );
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();
    await tester.tap(await _scrollToDataCategory(tester, 'large_category'));
    await tester.pumpAndSettle();

    expect(find.text('registratie-51'), findsNothing);
    final more = find.text('Meer tonen (1 resterend)');
    tester
        .widget<TextButton>(
          find.ancestor(of: more, matching: find.byType(TextButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('registratie-51'), findsOneWidget);
  });

  testWidgets('Mijn gegevens wordt na sluiten opnieuw live opgehaald', (
    tester,
  ) async {
    final notifier = _FixedOciServeNotifier(_authenticated);
    await _pumpApp(tester, notifier);
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();
    expect(notifier.privacyDataCalls, 1);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await _openCourses(tester);
    await tester.tap(find.text('Mijn gegevens'));
    await tester.pumpAndSettle();
    expect(notifier.privacyDataCalls, 2);
  });

  testWidgets('accountgegevens blijven zichtbaar zonder cursussen', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      _FixedOciServeNotifier(
        OciServeState(
          settings: const OciServeSettings(enabled: true),
          status: OciServeStatus.authenticated,
          account: OciServeAccount.fromJson(const {
            'account': {
              'id': 'learner',
              'display_name': 'Lerende',
              'email': 'lerende@example.nl',
            },
            'memberships': [
              {'organization_id': 'org', 'organization_name': 'Organisatie'},
            ],
          }),
        ),
        feed: const [],
        progress: const OciServeLearningState([]),
      ),
    );
    await _openCourses(tester);

    await tester.tap(find.text('Lerende'));
    await tester.pumpAndSettle();

    expect(find.textContaining('lerende@example.nl'), findsOneWidget);
    expect(find.textContaining('Organisatie'), findsOneWidget);
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
    expect(
      find.widgetWithText(FilledButton, 'Terug naar mijn cursussen'),
      findsOneWidget,
    );

    await _actUntil(
      tester,
      () => tester.tap(
        find.widgetWithText(FilledButton, 'Terug naar mijn cursussen'),
      ),
      () => find
          .byKey(const Key('ociserve-featured-course'))
          .evaluate()
          .isNotEmpty,
      'het cursusoverzicht verscheen niet opnieuw',
    );

    expect(container.read(tabsProvider).current?.isOpen, isFalse);
    expect(find.byKey(const Key('ociserve-featured-course')), findsOneWidget);
  });

  testWidgets('een cursusles kan direct terug naar het cursusoverzicht', (
    tester,
  ) async {
    final container = await _pumpApp(tester, _lessonNotifier());
    await _openCourses(tester);
    await tester.tap(find.text('Starten'));
    await tester.pumpAndSettle();

    final back = find.widgetWithText(
      OutlinedButton,
      'Terug naar mijn cursussen',
    );
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).current?.isOpen, isFalse);
    expect(find.byKey(const Key('ociserve-featured-course')), findsOneWidget);
  });

  testWidgets(
    'formeel examen toont alleen de huidige vraag en levert bewust in',
    (tester) async {
      await _pumpApp(tester, _lessonNotifier());
      await _openCourses(tester);
      await tester.tap(find.byKey(const Key('ociserve-exams-button')));
      await tester.pumpAndSettle();

      expect(find.text('Menselijk toezicht bij examens'), findsOneWidget);
      expect(
        find.textContaining('OciDeck stelt niet vast wie'),
        findsOneWidget,
      );
      await tester.tap(find.text('Start examen'));
      await tester.pumpAndSettle();

      expect(find.text('Welke letter?'), findsOneWidget);
      expect(find.text('Vraag 1'), findsOneWidget);
      expect(find.textContaining('correct'), findsNothing);
      await tester.tap(find.byType(RadioListTile<String>).first);
      await tester.pump();
      await tester.tap(find.text('Antwoord indienen'));
      await tester.pumpAndSettle();

      expect(find.text('Alle vragen zijn beantwoord.'), findsOneWidget);
      await tester.tap(find.text('Examen inleveren'));
      await tester.pumpAndSettle();
      expect(find.text('Examen inleveren?'), findsOneWidget);
      await tester.tap(find.text('Definitief inleveren'));
      await tester.pumpAndSettle();

      expect(find.text('Uw examen is ingeleverd.'), findsOneWidget);
    },
  );
}
