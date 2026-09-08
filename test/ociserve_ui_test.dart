import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_models.dart';
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
  });

  final OciServeState initial;
  final List<OciServeFeedItem> feed;
  final OciServeLearningState progress;
  final OciServePackage? package;
  final bool loginSucceeds;
  final Map<String, Uint8List> courseImages;
  Uint8List? accountAvatarBytes;
  PlaybackReport? reportedPlayback;
  bool loginCalled = false;

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
}
