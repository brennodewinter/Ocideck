// Een uitnodiging openen als handeling (FORM_INTAKE.md §6.6): het formulier komt als nieuw
// document in beeld, de pins worden bewaard, en wat de uitnodiging al aantoonde staat in het
// geheugen van de invulpagina — zodat het opslaan van de inzending er niet opnieuw om vraagt.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/intake/intake_client.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/forms/form_export_picker.dart';
import 'package:ocideck/widgets/forms/form_invitation_action.dart';
import 'package:ocideck/widgets/forms/form_invitation_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/intake_test_form.dart';
import 'support/pump_until.dart';

final DateTime _now = DateTime.utc(2026, 11, 3);

void main() {
  late Directory recoveryDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    FlutterSecureStorage.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
    debugClearPublishedForms();
    recoveryDir = Directory.systemTemp.createTempSync('ocideck_invite_');
    addTearDown(() {
      if (recoveryDir.existsSync()) recoveryDir.deleteSync(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  Future<ProviderContainer> pumpHarness(
    WidgetTester tester, {
    required IntakeClient client,
    required String link,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: recoveryDir),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openFormInvitation(
                  context,
                  client: client,
                  now: () => _now,
                  initialLink: link,
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
    return container;
  }

  /// Sluit de proef af: de tabbladen starten een tijdklok die alleen met de container stopt.
  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  Future<void> fetch(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('invitation-fetch')));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('invitation-open')).evaluate().isNotEmpty,
      reason: 'het formulier werd niet opgehaald',
    );
  }

  group('openFormInvitation', () {
    testWidgets(
      'opent het sjabloon als nieuw document en onthoudt wat de uitnodiging aantoonde',
      (tester) async {
        final f = (await tester.runAsync(() => serverWith(['nl'])))!;
        final container = await pumpHarness(
          tester,
          client: IntakeClient(f.server),
          link: f.organiser.invite().text,
        );
        await fetch(tester);
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();

        // Het sjabloon staat in een nieuw documenttabblad.
        final tab = container.read(tabsProvider).current!;
        expect(tab.documentNotifier!.state.document!.source, templateIn('nl'));
        expect(find.text('Formulier geopend.'), findsOneWidget);

        // De invulpagina vraagt niet om het bestand en niet om de vingerafdruk.
        final spec = (parseForm(templateIn('nl')) as ParsedForm).spec;
        final support = formExportSupportFor(
          projectPath: null,
          frontMatter: '',
          pickTitle: 't',
          saveTitle: 's',
          bundleTitle: 'b',
        );
        expect(support.recall(spec), templateIn('nl'));
        final seal = support.seal!.recall(spec)!;
        expect(seal.fingerprint, f.organiser.signing.fingerprint);
        expect((jsonDecode(seal.bundle) as Map)['fid'], kTestFid);
        // De bundel die onthouden is, is er een die de invulpagina gelooft.
        final verified = await tester.runAsync(
          () => verifyFormBundle(
            seal.bundle,
            templateText: templateIn('nl'),
            fingerprint: seal.fingerprint,
            now: _now,
            expectedApiHost: 'intake.example.org',
          ),
        );
        expect(verified, isA<FormBundleVerified>());
        await finish(tester, container);
      },
    );

    testWidgets('bewaart de pins zodra het formulier is geopend', (
      tester,
    ) async {
      final f = (await tester.runAsync(() => serverWith(['nl', 'en'])))!;
      final container = await pumpHarness(
        tester,
        client: IntakeClient(f.server),
        link: f.organiser.invite().text,
      );
      await fetch(tester);
      await tester.tap(find.byKey(const Key('invitation-open')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(kFormBundlePinsKey)!), {
        '$kTestFid@${f.organiser.signing.fingerprint}': 3,
      });
      await finish(tester, container);
    });

    testWidgets(
      'de talen van één formulier overschrijven elkaars geheugen niet',
      (tester) async {
        final f = (await tester.runAsync(() => serverWith(['nl', 'en'])))!;
        final container = await pumpHarness(
          tester,
          client: IntakeClient(f.server),
          link: f.organiser.invite().text,
        );
        await fetch(tester);
        await tester.tap(
          find.byKey(const Key('invitation-open')),
        ); // nl, voorgekozen
        await tester.pumpAndSettle();
        // Een tweede uitnodiging, nu in het Engels.
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await fetch(tester);
        await tester.tap(find.byKey(const Key('invitation-variant-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();

        final support = formExportSupportFor(
          projectPath: null,
          frontMatter: '',
          pickTitle: 't',
          saveTitle: 's',
          bundleTitle: 'b',
        );
        final nl = (parseForm(templateIn('nl')) as ParsedForm).spec;
        final en = (parseForm(templateIn('en')) as ParsedForm).spec;
        expect(support.recall(nl), templateIn('nl'));
        expect(support.recall(en), templateIn('en'));
        expect(
          (jsonDecode(support.seal!.recall(nl)!.bundle)
              as Map)['template_sha256'],
          formTemplateHash(templateIn('nl')),
        );
        expect(
          (jsonDecode(support.seal!.recall(en)!.bundle)
              as Map)['template_sha256'],
          formTemplateHash(templateIn('en')),
        );
        await finish(tester, container);
      },
    );

    testWidgets('annuleren laat niets achter', (tester) async {
      final f = (await tester.runAsync(() => serverWith(['nl'])))!;
      final container = await pumpHarness(
        tester,
        client: IntakeClient(f.server),
        link: f.organiser.invite().text,
      );
      final tabsBefore = container.read(tabsProvider).tabs.length;
      await fetch(tester);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();

      expect(container.read(tabsProvider).tabs, hasLength(tabsBefore));
      final spec = (parseForm(templateIn('nl')) as ParsedForm).spec;
      final support = formExportSupportFor(
        projectPath: null,
        frontMatter: '',
        pickTitle: 't',
        saveTitle: 's',
        bundleTitle: 'b',
      );
      expect(support.recall(spec), isNull);
      expect(support.seal!.recall(spec), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kFormBundlePinsKey), isNull);
      expect(find.text('Formulier geopend.'), findsNothing);
      await finish(tester, container);
    });

    testWidgets('een formulier dat niet openging laat niets achter', (
      tester,
    ) async {
      final f = (await tester.runAsync(() => serverWith(['nl'])))!;
      f.server.forms.clear();
      final container = await pumpHarness(
        tester,
        client: IntakeClient(f.server),
        link: f.organiser.invite().text,
      );
      final tabsBefore = container.read(tabsProvider).tabs.length;
      await tester.tap(find.byKey(const Key('invitation-fetch')));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('invitation-failure')).evaluate().isNotEmpty,
        reason: 'er kwam geen melding',
      );
      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(container.read(tabsProvider).tabs, hasLength(tabsBefore));
      expect(
        (await SharedPreferences.getInstance()).getString(kFormBundlePinsKey),
        isNull,
      );
      await finish(tester, container);
    });
  });

  group('het startscherm', () {
    Future<void> pumpWelcome(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'heeft een knop Uitnodiging openen…, ook zonder de uitbreiding voor formulieren',
      (tester) async {
        await pumpWelcome(tester);
        expect(find.text('Uitnodiging openen…'), findsOneWidget);
        // De uitbreiding is uit: de Inbox van een organisator staat er niet.
        expect(find.text('Inzendingen'), findsNothing);
      },
    );

    testWidgets('de knop opent het venster', (tester) async {
      await pumpWelcome(tester);
      await tester.tap(find.text('Uitnodiging openen…'));
      await tester.pumpAndSettle();
      expect(find.byType(FormInvitationDialog), findsOneWidget);
      expect(find.byKey(const Key('invitation-link')), findsOneWidget);
    });
  });
}
