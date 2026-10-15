import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/ociserve_theme.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/widgets/dialogs/ociserve_invitation_dialog.dart';
import 'package:ocideck/widgets/dialogs/ociserve_org_themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ociserve_fake_gateway.dart';

/// De uitnodigingswizard (#2425) en het themaregister (#2429) als gebruiker:
/// de stappen, de weigeringen in begrijpelijke taal, en dat een gevaarlijke
/// handeling (delen, overschrijven) altijd eerst een bevestiging vraagt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOciServeApi api;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    api = newOciServeApi();
    container = ProviderContainer(overrides: ociserveTestOverrides(api));
    addTearDown(container.dispose);
  });

  Future<void> pumpApp(
    WidgetTester tester,
    Widget Function(BuildContext) open,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: open)),
        ),
      ),
    );
  }

  Future<void> signIn() async {
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(ociserveTestSettings);
    await notifier.login();
  }

  /// Een begrensde pomp: tijdens delen draait een spinner, en `pumpAndSettle`
  /// wacht dan eindeloos op een animatie die pas stopt als de actie klaar is.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('uitnodigingswizard', () {
    Future<void> openWizard(WidgetTester tester) async {
      // De uitnodigingsknop hoort bij een ingeschakelde eLearning-module.
      await container
          .read(ociServeProvider.notifier)
          .saveSettings(ociserveTestSettings);
      await pumpApp(
        tester,
        (c) => TextButton(
          onPressed: () => OciServeInvitationDialog.show(c),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> fillCodes(WidgetTester tester) async {
      await tester.enterText(field('Uitnodigingsnummer'), ' inv-1 ');
      await tester.enterText(field('Uitnodigingscode'), ' s3cret ');
    }

    testWidgets('nieuwe deelnemer: codes, dan registreren, dan aangemeld', (
      tester,
    ) async {
      api.handlers[#invitationRegistrationPreview] = (_) async =>
          'sam@example.org';
      api.handlers[#invitationRegister] = (_) async =>
          const OciServeInvitationResult(organizationId: 'org', role: 'member');
      await openWizard(tester);

      expect(field('eLearning-server'), findsOneWidget);
      await fillCodes(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      // De codes zijn getrimd vóór ze de deur uit gaan.
      expect(api.arg(#invitationRegistrationPreview, #invitationId), 'inv-1');
      expect(api.arg(#invitationRegistrationPreview, #secret), 's3cret');
      expect(find.textContaining('sam@example.org'), findsOneWidget);

      await tester.enterText(field('Uw naam'), 'Sam');
      await tester.enterText(field('Wachtwoord'), 'een-lang-wachtwoord');
      await tester.enterText(
        field('Wachtwoord herhalen'),
        'een-lang-wachtwoord',
      );
      await tester.tap(find.text('Registreren en aanmelden'));
      await tester.pumpAndSettle();

      expect(api.arg(#invitationRegister, #displayName), 'Sam');
      expect(api.arg(#invitationRegister, #idempotencyKey), isA<String>());
      expect(
        find.text('U bent geregistreerd en aangemeld. Welkom!'),
        findsOneWidget,
      );
      expect(container.read(ociServeProvider).authenticated, isTrue);

      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.byType(OciServeInvitationDialog), findsNothing);
    });

    testWidgets('een verkeerde combinatie krijgt één generieke melding', (
      tester,
    ) async {
      api.handlers[#invitationRegistrationPreview] = (_) async =>
          throw const OciServeException('ongeldig', statusCode: 400);
      await openWizard(tester);
      await fillCodes(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('klopt niet, of de uitnodiging is verlopen'),
        findsOneWidget,
      );
      // Je blijft op de eerste stap en kunt opnieuw proberen.
      expect(field('Uitnodigingscode'), findsOneWidget);
    });

    testWidgets('te veel pogingen en een onbekende fout hebben eigen woorden', (
      tester,
    ) async {
      api.handlers[#invitationRegistrationPreview] = (_) async =>
          throw const OciServeException('traag', statusCode: 429);
      await openWizard(tester);
      await fillCodes(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Te veel pogingen'), findsOneWidget);

      api.handlers[#invitationRegistrationPreview] = (_) async =>
          throw StateError('onverwacht');
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dat is niet gelukt. Probeer het opnieuw.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'het wachtwoord wordt gecontroleerd voordat er iets verstuurd wordt',
      (tester) async {
        api.handlers[#invitationRegistrationPreview] = (_) async =>
            'sam@example.org';
        await openWizard(tester);
        await fillCodes(tester);
        await tester.tap(find.text('Doorgaan'));
        await tester.pumpAndSettle();

        Future<void> submit() async {
          await tester.tap(find.text('Registreren en aanmelden'));
          await tester.pumpAndSettle();
        }

        await tester.enterText(field('Wachtwoord'), 'kort');
        await submit();
        expect(
          find.text('Kies een wachtwoord van minstens 12 tekens.'),
          findsOneWidget,
        );

        await tester.enterText(field('Wachtwoord'), 'een-lang-wachtwoord');
        await tester.enterText(
          field('Wachtwoord herhalen'),
          'iets-anders-lang',
        );
        await submit();
        expect(
          find.text('De wachtwoorden zijn niet hetzelfde.'),
          findsOneWidget,
        );

        await tester.enterText(
          field('Wachtwoord herhalen'),
          'een-lang-wachtwoord',
        );
        await submit();
        expect(find.text('Vul uw naam in.'), findsOneWidget);
        expect(api.calls, isNot(contains(#invitationRegister)));
      },
    );

    testWidgets('het wachtwoord is verborgen en kan getoond worden', (
      tester,
    ) async {
      api.handlers[#invitationRegistrationPreview] = (_) async =>
          'sam@example.org';
      await openWizard(tester);
      await fillCodes(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      TextField pw() => tester.widget<TextField>(field('Wachtwoord'));
      expect(pw().obscureText, isTrue);
      await tester.tap(find.byTooltip('Wachtwoord tonen').first);
      await tester.pump();
      expect(pw().obscureText, isFalse);
    });

    testWidgets(
      'een mislukte registratie meldt dat en laat het formulier staan',
      (tester) async {
        api.handlers[#invitationRegistrationPreview] = (_) async =>
            'sam@example.org';
        api.handlers[#invitationRegister] = (_) async =>
            throw const OciServeException('x', statusCode: 400);
        await openWizard(tester);
        await fillCodes(tester);
        await tester.tap(find.text('Doorgaan'));
        await tester.pumpAndSettle();
        await tester.enterText(field('Uw naam'), 'Sam');
        await tester.enterText(field('Wachtwoord'), 'een-lang-wachtwoord');
        await tester.enterText(
          field('Wachtwoord herhalen'),
          'een-lang-wachtwoord',
        );
        await tester.tap(find.text('Registreren en aanmelden'));
        await tester.pumpAndSettle();
        expect(find.textContaining('klopt niet'), findsOneWidget);
        expect(find.text('Registreren en aanmelden'), findsOneWidget);
      },
    );

    testWidgets(
      'aangemeld: accepteren met het bestaande account, zonder server of wachtwoord',
      (tester) async {
        api.handlers[#invitationAccept] = (_) async =>
            const OciServeInvitationResult(
              organizationId: 'org-2',
              role: 'member',
            );
        await signIn();
        await openWizard(tester);
        expect(field('eLearning-server'), findsNothing);
        await fillCodes(tester);
        await tester.tap(find.text('Doorgaan'));
        await tester.pumpAndSettle();
        expect(api.calls, isNot(contains(#invitationRegistrationPreview)));
        expect(
          find.textContaining('De uitnodiging is geaccepteerd'),
          findsOneWidget,
        );
      },
    );

    testWidgets('aangemeld en geweigerd: dezelfde generieke melding', (
      tester,
    ) async {
      api.handlers[#invitationAccept] = (_) async =>
          throw const OciServeException('x', statusCode: 400);
      await signIn();
      await openWizard(tester);
      await fillCodes(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('klopt niet'), findsOneWidget);
    });

    testWidgets('sluiten kan met het kruisje voordat er iets is gedaan', (
      tester,
    ) async {
      await openWizard(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(OciServeInvitationDialog), findsNothing);
    });
  });

  group('thema’s van de organisatie', () {
    const profile = ThemeProfile(name: 'Huisstijl');
    final definition = profile.toJson();
    OciServeTheme theme(String id, String name, {bool builtin = false}) =>
        OciServeTheme(
          id: id,
          name: name,
          definition: definition,
          isBuiltin: builtin,
        );

    ThemeProfile? adopted;

    Future<void> openThemes(WidgetTester tester) async {
      adopted = null;
      await pumpApp(
        tester,
        (c) => TextButton(
          onPressed: () => OciServeOrgThemes.show(
            c,
            current: profile,
            onAdopt: (p) => adopted = p,
          ),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    void serve(List<OciServeTheme> themes) {
      api.handlers[#themes] = (_) async => (themes: themes, nextCursor: null);
    }

    testWidgets('toont de thema’s; ingebouwde zijn niet te verwijderen', (
      tester,
    ) async {
      serve([theme('a', 'Eigen'), theme('b', 'Standaard', builtin: true)]);
      await signIn();
      await openThemes(tester);
      expect(find.text('Eigen'), findsOneWidget);
      expect(find.text('Ingebouwd'), findsOneWidget);
      expect(find.byTooltip('Verwijderen bij de organisatie'), findsOneWidget);
    });

    testWidgets('een lege organisatie zegt dat', (tester) async {
      serve(const []);
      await signIn();
      await openThemes(tester);
      expect(
        find.text('De organisatie heeft nog geen eigen thema’s.'),
        findsOneWidget,
      );
    });

    testWidgets('niet kunnen laden is een melding, geen lege lijst', (
      tester,
    ) async {
      api.handlers[#themes] = (_) async =>
          throw const OciServeException('x', statusCode: 500);
      await signIn();
      await openThemes(tester);
      expect(
        find.textContaining('konden niet worden opgehaald'),
        findsOneWidget,
      );
    });

    testWidgets('overnemen geeft het profiel door en sluit het venster', (
      tester,
    ) async {
      serve([theme('a', 'Eigen')]);
      await signIn();
      await openThemes(tester);
      await tester.tap(find.text('Overnemen'));
      await tester.pumpAndSettle();
      expect(adopted?.name, 'Huisstijl');
      expect(find.byType(OciServeOrgThemes), findsNothing);
    });

    testWidgets(
      'delen vraagt eerst een bevestiging met de volledige definitie',
      (tester) async {
        serve(const []);
        api.handlers[#createTheme] = (_) async => theme('n', 'Huisstijl');
        await signIn();
        await openThemes(tester);
        await tester.tap(find.textContaining('delen met de organisatie'));
        await tester.pumpAndSettle();
        expect(
          find.text('Stijlprofiel delen met de organisatie?'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Dit is de volledige definitie'),
          findsOneWidget,
        );
        expect(
          api.calls,
          isNot(contains(#createTheme)),
          reason: 'nog niets verstuurd',
        );

        await tester.tap(find.text('Delen'));
        await settle(tester);
        expect(api.arg(#createTheme, #name), 'Huisstijl');
      },
    );

    testWidgets('annuleren bij de bevestiging verstuurt niets', (tester) async {
      serve(const []);
      await signIn();
      await openThemes(tester);
      await tester.tap(find.textContaining('delen met de organisatie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains(#createTheme)));
    });

    testWidgets('een bestaande naam wordt een voorstel om bij te werken', (
      tester,
    ) async {
      serve([theme('a', 'Huisstijl')]);
      api.handlers[#createTheme] = (_) async =>
          throw const OciServeException('bestaat', statusCode: 409);
      api.handlers[#theme] = (_) async =>
          (theme: theme('a', 'Huisstijl'), etag: '"e1"');
      api.handlers[#updateTheme] = (_) async =>
          (theme: theme('a', 'Huisstijl'), etag: '"e2"');
      await signIn();
      await openThemes(tester);
      await tester.tap(find.textContaining('delen met de organisatie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delen'));
      await settle(tester);
      expect(find.text('Naam is al in gebruik'), findsOneWidget);
      await tester.tap(find.text('Bijwerken'));
      await settle(tester);
      expect(api.arg(#updateTheme, #ifMatch), '"e1"');
    });

    testWidgets(
      'nee zeggen op het bijwerk-voorstel laat de serverversie staan',
      (tester) async {
        serve([theme('a', 'Huisstijl')]);
        api.handlers[#createTheme] = (_) async =>
            throw const OciServeException('bestaat', statusCode: 409);
        await signIn();
        await openThemes(tester);
        await tester.tap(find.textContaining('delen met de organisatie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delen'));
        await settle(tester);
        await tester.tap(find.text('Annuleren'));
        await tester.pumpAndSettle();
        expect(api.calls, isNot(contains(#updateTheme)));
      },
    );

    testWidgets(
      'een naamconflict zonder zichtbaar thema geeft een duidelijke melding',
      (tester) async {
        serve(const []);
        api.handlers[#createTheme] = (_) async =>
            throw const OciServeException('bestaat', statusCode: 409);
        await signIn();
        await openThemes(tester);
        await tester.tap(find.textContaining('delen met de organisatie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delen'));
        await settle(tester);
        expect(
          find.textContaining('Er bestaat al een thema met deze naam'),
          findsOneWidget,
        );
      },
    );

    Future<void> reachEtagConflict(WidgetTester tester) async {
      serve([theme('a', 'Huisstijl')]);
      api.handlers[#createTheme] = (_) async =>
          throw const OciServeException('bestaat', statusCode: 409);
      api.handlers[#theme] = (_) async =>
          (theme: theme('a', 'Huisstijl'), etag: '"e1"');
      var updates = 0;
      api.handlers[#updateTheme] = (_) async {
        updates++;
        if (updates == 1) {
          throw const OciServeException('veranderd', statusCode: 409);
        }
        return (theme: theme('a', 'Huisstijl'), etag: '"e3"');
      };
      await signIn();
      await openThemes(tester);
      await tester.tap(find.textContaining('delen met de organisatie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delen'));
      await settle(tester);
      await tester.tap(find.text('Bijwerken'));
      await settle(tester);
      expect(find.text('Tussendoor gewijzigd'), findsOneWidget);
    }

    testWidgets(
      'na een wijziging onderweg kies je: overschrijven forceert If-Match *',
      (tester) async {
        await reachEtagConflict(tester);
        await tester.tap(find.text('Overschrijven'));
        await settle(tester);
        expect(api.arg(#updateTheme, #ifMatch), '*');
      },
    );

    testWidgets('of je neemt de serverversie over', (tester) async {
      await reachEtagConflict(tester);
      await tester.tap(find.text('Serverversie overnemen'));
      await settle(tester);
      expect(adopted?.name, 'Huisstijl');
    });

    testWidgets('weigering door rechten krijgt een eigen melding', (
      tester,
    ) async {
      serve(const []);
      api.handlers[#createTheme] = (_) async =>
          throw const OciServeException('nee', statusCode: 403);
      await signIn();
      await openThemes(tester);
      await tester.tap(find.textContaining('delen met de organisatie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delen'));
      await settle(tester);
      expect(find.textContaining('mag geen thema’s beheren'), findsOneWidget);
    });

    testWidgets(
      'verwijderen laadt de lijst opnieuw; ingebouwd of in gebruik legt het uit',
      (tester) async {
        serve([theme('a', 'Eigen')]);
        api.handlers[#deleteTheme] = (_) async => null;
        await signIn();
        await openThemes(tester);
        await tester.tap(find.byTooltip('Verwijderen bij de organisatie'));
        await tester.pumpAndSettle();
        expect(api.arg(#deleteTheme, #themeId), 'a');

        api.handlers[#deleteTheme] = (_) async =>
            throw const OciServeException('in gebruik', statusCode: 409);
        await tester.tap(find.byTooltip('Verwijderen bij de organisatie'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ingebouwd of in gebruik'), findsOneWidget);
      },
    );
  });
}
