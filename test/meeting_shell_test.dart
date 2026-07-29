import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/providers/fake/fake_meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/state/meetings_module_provider.dart';
import 'package:ocideck/widgets/meetings/meeting_failure_text.dart';
import 'package:ocideck/widgets/meetings/meeting_join_dialog.dart';
import 'package:ocideck/widgets/meetings/meeting_shell_chrome.dart';
import 'package:ocideck/widgets/meetings/meeting_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De schil van T14/T15: herkennen tijdens het typen, de bekendmaking vóór de
/// knop, wachten in de omlijsting, en knoppen die alleen uit de rechten komen.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    // Een test die eindigt met het gespreksvenster nog open laat de rem op
    // 'zichtbaar' staan; zonder deze reset kan de volgende test er geen meer
    // openen en hangt de uitkomst van de testvolgorde af.
    debugResetMeetingWorkspaceVisible();
  });

  /// Pomp een paar frames in plaats van uit te settelen.
  ///
  /// Nodig zodra het statuslampje in beeld is: dat knippert in de verbindende
  /// fasen, en dat is met opzet een animatie die niet stopt zolang de uitkomst
  /// onbekend is (T15). `pumpAndSettle` wacht op een boom die tot rust komt en
  /// loopt daarom af in een tijdslimiet — niet omdat er iets stuk is.
  Future<void> settle(WidgetTester tester, {int frames = 4}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Zet een widget in een scope neer en geef de container terug, zodat een
  /// test de sessie kan aansturen zoals een adapter dat zou doen.
  Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  group('de faalteksten (§18)', () {
    test('elke faalsoort heeft een eigen, niet-lege uitleg', () {
      const l10n = AppLocalizations(Locale('nl'));
      final seen = <String>{};
      for (final kind in MeetingFailureKind.values) {
        final text = meetingFailureText(l10n, kind);
        expect(text, isNotEmpty, reason: '$kind hoort een uitleg te hebben');
        expect(
          seen.add(text),
          isTrue,
          reason: '$kind hergebruikt de tekst van een andere faalsoort',
        );
      }
    });

    test('geen enkele uitleg noemt een leverancier of een servercode', () {
      const l10n = AppLocalizations(Locale('nl'));
      for (final kind in MeetingFailureKind.values) {
        final text = meetingFailureText(l10n, kind).toLowerCase();
        for (final vendor in ['teams', 'microsoft', 'zoom', 'webex', 'jitsi']) {
          expect(
            text.contains(vendor),
            isFalse,
            reason:
                '$kind noemt $vendor; de schil is aanbieder-neutraal (T14) en '
                'de dienstnaam hoort uit de adapter te komen',
          );
        }
      }
    });

    test('elke fase heeft een label, behalve idle', () {
      expect(meetingPhaseLabelOf(MeetingPhase.idle), isNull);
      const l10n = AppLocalizations(Locale('nl'));
      for (final phase in MeetingPhase.values) {
        if (phase == MeetingPhase.idle) continue;
        final label = meetingPhaseLabelOf(phase);
        expect(label, isNotNull, reason: '$phase hoort een label te hebben');
        expect(meetingPhaseLabel(l10n, label!), isNotEmpty);
      }
    });

    test('wachten en verbonden zijn in tekst verschillend', () {
      const l10n = AppLocalizations(Locale('nl'));
      expect(
        meetingPhaseLabel(l10n, MeetingPhaseLabel.waitingForAdmission),
        isNot(meetingPhaseLabel(l10n, MeetingPhaseLabel.connected)),
      );
    });
  });

  group('de gast-waarschuwing volgt de adapter, niet een vaste zin', () {
    test('zonder feiten van een adapter is de gastaanname eerlijk', () {
      expect(showsUnverifiedNameHint(null), isTrue);
      expect(
        showsUnverifiedNameHint(MeetingIdentityKind.anonymousDisplayName),
        isTrue,
      );
      expect(
        showsUnverifiedNameHint(MeetingIdentityKind.ephemeralGuest),
        isTrue,
      );
    });

    test('bij een echte identiteit verdwijnt de waarschuwing', () {
      // Anders staan er twee elkaar tegensprekende beweringen boven dezelfde
      // Meedoen-knop: "de anderen zien u als gast" naast "meedoen gaat met uw
      // eigen account bij deze aanbieder".
      for (final identity in [
        MeetingIdentityKind.serviceAppGuest,
        MeetingIdentityKind.hostSponsored,
        MeetingIdentityKind.account,
      ]) {
        expect(
          showsUnverifiedNameHint(identity),
          isFalse,
          reason:
              'bij $identity is "niemand controleert deze naam" niet waar; de '
              'bekendmaking hoort dat te zeggen, niet een vaste zin',
        );
      }
    });

    test('elke identiteitssoort heeft een antwoord', () {
      // De switch is gesloten: een nieuwe identiteitssoort dwingt een keuze in
      // plaats van stil in de gast-tak te vallen.
      for (final identity in MeetingIdentityKind.values) {
        expect(() => showsUnverifiedNameHint(identity), returnsNormally);
      }
    });
  });

  group('de deelnamedialoog', () {
    testWidgets('herkennen gebeurt tijdens het typen en raakt de sessie niet '
        'aan', (tester) async {
      final container = await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/direct',
      );
      await tester.pumpAndSettle();
      // Meteen een oordeel, zonder knop en zonder netwerk…
      expect(
        find.textContaining('Herkend als een vergadering'),
        findsOneWidget,
      );
      // …en de sessie staat nog op niets: een halve link is geen mislukte
      // vergadering, en de wachtstrip hoort dus niet te verschijnen.
      expect(container.read(meetingSessionProvider).phase, MeetingPhase.idle);
      expect(container.read(meetingSessionActiveProvider), isFalse);
    });

    testWidgets('een afgewezen link krijgt zijn eigen uitleg, ook al tijdens '
        'het typen', (tester) async {
      await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'http://$fakeMeetingHost/j/direct',
      );
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));
      expect(
        find.text(meetingFailureText(l10n, MeetingFailureKind.invalidLink)),
        findsOneWidget,
      );
    });

    testWidgets('de bekendmaking staat vóór de knop, en Meedoen verschijnt pas '
        'daarna', (tester) async {
      await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));

      // Zolang er niet gecontroleerd is, is er geen Meedoen.
      expect(find.text(l10n.d('Meedoen')), findsNothing);
      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/lobby',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.d('Controleren')));
      await tester.pumpAndSettle();

      // De bekendmaking van §6.2 stap 4: wie krijgt contact, wat ziet die, en
      // dat de wachtruimte te verwachten is.
      expect(find.text(l10n.d('Wat er gebeurt als u meedoet')), findsOneWidget);
      expect(find.textContaining(fakeMeetingHost), findsWidgets);
      expect(find.textContaining('wachtruimte'), findsOneWidget);
      // T9: bij een adapter die niets weet, staat dat er eerlijk bij.
      expect(find.textContaining('niets vastgesteld'), findsOneWidget);
      expect(find.text(l10n.d('Meedoen')), findsOneWidget);
    });

    testWidgets('meedoen kan niet zonder naam', (tester) async {
      await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));
      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/direct',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.d('Controleren')));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.d('Meedoen')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('de hele reis: link, naam, controleren, meedoen', (
      tester,
    ) async {
      final container = await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));
      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/direct',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.d('Controleren')));
      await tester.pumpAndSettle();

      // Een naam typen maakt Meedoen bruikbaar. Zonder deze stap zou een
      // ontbrekende `onChanged` op het naamveld onopgemerkt blijven — en dan
      // blijft de knop grijs en is meedoen onmogelijk.
      await tester.enterText(find.byType(TextField).last, 'Kim');
      await tester.pumpAndSettle();
      final knop = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.d('Meedoen')),
      );
      expect(knop.onPressed, isNotNull);

      await tester.tap(find.text(l10n.d('Meedoen')));
      await tester.pumpAndSettle();
      // De adapter heeft het overgenomen, en het venster is weg: wat er daarna
      // gebeurt hoort in de omlijsting (T15).
      expect(
        container.read(meetingSessionProvider.notifier).session,
        isNotNull,
      );
      expect(find.byType(MeetingJoinDialog), findsNothing);
      // De fasen van §6.2 zijn gezet — zonder die reeks zou `join` stil op de
      // fasepoort afketsen en zou er niets gebeuren, ook niet zichtbaar.
      expect(
        container.read(meetingSessionProvider).phase,
        MeetingPhase.provisioning,
      );
    });

    testWidgets('annuleren annuleert ook echt: geen sessie blijft hangen', (
      tester,
    ) async {
      final container = await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));
      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/direct',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.d('Controleren')));
      await tester.pumpAndSettle();
      // Na Controleren staat de uitnodiging in de sessie en geldt die als
      // actief.
      expect(container.read(meetingSessionActiveProvider), isTrue);

      await tester.tap(find.text(l10n.d('Annuleren')));
      await tester.pumpAndSettle();
      // Zonder opruimen bleef de fase op `validating` staan: het startpunt in
      // de tabbalk verbergt zich dan (er loopt "al" een vergadering) en de
      // wachtstrip toont zich in die fase niet — een doodlopende weg waar
      // alleen een herstart uit hielp.
      expect(container.read(meetingSessionActiveProvider), isFalse);
      expect(container.read(meetingSessionProvider).phase, MeetingPhase.idle);
    });

    testWidgets('een geweigerde gast leest de reden in de bekendmaking', (
      tester,
    ) async {
      await pump(tester, const _DialogHost());
      await tester.tap(find.text('Openen'));
      await tester.pumpAndSettle();
      const l10n = AppLocalizations(Locale('nl'));
      await tester.enterText(
        find.byType(TextField).first,
        'https://$fakeMeetingHost/j/guestDisabled',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.d('Controleren')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          meetingFailureText(l10n, MeetingFailureKind.anonymousJoinDisabled),
        ),
        findsOneWidget,
      );
      // Meedoen blijft dicht — de knop staat er wél, want hij vertelt de
      // gebruiker wat hij probeerde; hij doet alleen niets. De reden staat
      // erboven, dus een verdwenen knop zou de uitleg losmaken van de daad.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.d('Meedoen')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('het startpunt en het lampje (T13, T15)', () {
    testWidgets('met de module uit is er geen startpunt', (tester) async {
      await pump(tester, const MeetingEntryPoint());
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });

    testWidgets('met de module aan verschijnt het startpunt', (tester) async {
      final container = await pump(tester, const MeetingEntryPoint());
      await container.read(meetingsModuleProvider.notifier).setEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('het lampje verschijnt pas bij een gesprek, en wijkt per fase '
        'af in pictogram', (tester) async {
      final container = await pump(tester, const MeetingStatusIndicator());
      expect(find.byType(Icon), findsNothing);

      final notifier = container.read(meetingSessionProvider.notifier);
      notifier.resolveLink('https://$fakeMeetingHost/j/lobby');
      notifier.requestDevicePermission();
      notifier.devicesReady();
      await notifier.join(displayName: 'Tester');
      final session = notifier.session! as FakeMeetingSession;
      session.advance(); // connecting
      session.advance(); // lobby
      await settle(tester);
      // De wachtruimte heeft haar eigen pictogram — niet dat van "verbonden".
      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);

      session.advanceAll();
      await settle(tester);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.pets), findsNothing);
    });

    testWidgets('de wachtstrip meldt het wachten en biedt Verlaten', (
      tester,
    ) async {
      final container = await pump(tester, const MeetingWaitingStrip());
      const l10n = AppLocalizations(Locale('nl'));
      expect(find.text(l10n.d('Verlaten')), findsNothing);

      final notifier = container.read(meetingSessionProvider.notifier);
      notifier.resolveLink('https://$fakeMeetingHost/j/lobby');
      notifier.requestDevicePermission();
      notifier.devicesReady();
      await notifier.join(displayName: 'Tester');
      final session = notifier.session! as FakeMeetingSession;
      session.advance();
      session.advance();
      await settle(tester);
      expect(find.textContaining('moet u nog toelaten'), findsOneWidget);
      expect(find.text(l10n.d('Verlaten')), findsOneWidget);
    });

    testWidgets('bij verbonden verdwijnt de strip: er is niets om op te '
        'wachten', (tester) async {
      final container = await pump(tester, const MeetingWaitingStrip());
      final notifier = container.read(meetingSessionProvider.notifier);
      notifier.resolveLink('https://$fakeMeetingHost/j/direct');
      notifier.requestDevicePermission();
      notifier.devicesReady();
      await notifier.join(displayName: 'Tester');
      (notifier.session! as FakeMeetingSession).advanceAll();
      await settle(tester);
      expect(
        container.read(meetingSessionProvider).phase,
        MeetingPhase.connected,
      );
      expect(find.byType(MeetingWaitingStrip), findsOneWidget);
      // De widget staat er, maar tekent niets: geen tekst, geen knop.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('een mislukking blijft staan tot de gebruiker haar wegklikt', (
      tester,
    ) async {
      final container = await pump(tester, const MeetingWaitingStrip());
      const l10n = AppLocalizations(Locale('nl'));
      container.read(meetingSessionProvider.notifier).resolveLink('geen link');
      await tester.pumpAndSettle();
      expect(
        find.text(meetingFailureText(l10n, MeetingFailureKind.invalidLink)),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.d('Sluiten')));
      await tester.pumpAndSettle();
      expect(container.read(meetingSessionActiveProvider), isFalse);
    });
  });

  group('de toelatingswaker (§6.3)', () {
    /// De waker moet in een boom mét Navigator staan, want hij opent een route.
    Future<ProviderContainer> pumpWatcher(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: MeetingAdmissionWatcher())),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    }

    Future<FakeMeetingSession> start(
      ProviderContainer container,
      String scenario,
    ) async {
      final notifier = container.read(meetingSessionProvider.notifier);
      notifier.resolveLink('https://$fakeMeetingHost/j/$scenario');
      notifier.requestDevicePermission();
      notifier.devicesReady();
      await notifier.join(displayName: 'Tester');
      return notifier.session! as FakeMeetingSession;
    }

    testWidgets('toelating opent het gespreksvenster zonder dat de gebruiker '
        'iets hoeft te doen', (tester) async {
      final container = await pumpWatcher(tester);
      final session = await start(container, 'lobby');
      session.advance(); // connecting
      session.advance(); // lobby
      await settle(tester);
      // Nog niets: er is niets om te zien zolang er gewacht wordt (T15).
      expect(find.byType(MeetingWorkspaceDialog), findsNothing);

      session.advanceAll(); // de organisator laat toe
      await settle(tester);
      // Zonder dit venster is een pictogramwissel van 16 pixels het enige
      // signaal dat de gebruiker binnen is — mét een microfoon die volgens de
      // dienst meedoet.
      expect(find.byType(MeetingWorkspaceDialog), findsOneWidget);
    });

    testWidgets('een herverbinding dringt geen venster op', (tester) async {
      final container = await pumpWatcher(tester);
      final session = await start(container, 'reconnect');
      session.advanceAll();
      await settle(tester);
      // Het verloop gaat connecting → connected → reconnecting → connected.
      // Het eerste 'connected' opent het venster; sluit dat, en de terugkeer
      // uit de herverbinding mag het niet opnieuw opdringen.
      expect(find.byType(MeetingWorkspaceDialog), findsOneWidget);
      final l10n = AppLocalizations(Locale('nl'));
      await tester.tap(find.text(l10n.d('Venster sluiten')));
      // Een route die wegschuift heeft meer dan vier frames nodig.
      await settle(tester, frames: 12);
      expect(find.byType(MeetingWorkspaceDialog), findsNothing);
      expect(
        container.read(meetingSessionProvider).phase,
        MeetingPhase.connected,
      );
    });

    testWidgets('er komt nooit een tweede venster op het eerste', (
      tester,
    ) async {
      final container = await pumpWatcher(tester);
      final session = await start(container, 'lobby');
      // De gebruiker opent het venster zelf terwijl hij nog wacht. Niet
      // awaiten: `show` keert pas terug als het venster weer dicht is, dus
      // wachten zou de test laten hangen.
      unawaited(
        MeetingWorkspaceDialog.show(tester.element(find.byType(Scaffold))),
      );
      await settle(tester);
      expect(find.byType(MeetingWorkspaceDialog), findsOneWidget);
      // …en wordt daarna toegelaten. De waker mag er geen tweede bovenop
      // zetten: Verlaten zou dan het onderste venster laten staan.
      session.advanceAll();
      await settle(tester);
      expect(find.byType(MeetingWorkspaceDialog), findsOneWidget);
    });
  });

  group('het gespreksvenster', () {
    /// Breng de sessie tot `connected` met het gevraagde verloop.
    Future<FakeMeetingSession> connect(
      ProviderContainer container,
      String scenario,
    ) async {
      final notifier = container.read(meetingSessionProvider.notifier);
      notifier.resolveLink('https://$fakeMeetingHost/j/$scenario');
      notifier.requestDevicePermission();
      notifier.devicesReady();
      await notifier.join(displayName: 'Tester');
      return notifier.session! as FakeMeetingSession;
    }

    testWidgets('knoppen komen uit de rechten, en Verlaten staat er altijd', (
      tester,
    ) async {
      final container = await pump(tester, const MeetingWorkspaceDialog());
      const l10n = AppLocalizations(Locale('nl'));
      // Zonder gesprek: geen bedieningsknoppen, wél Verlaten (§17).
      expect(find.text(l10n.d('Microfoon aanzetten')), findsNothing);
      expect(find.text(l10n.d('Verlaten')), findsOneWidget);

      final session = await connect(container, 'direct');
      session.advanceAll();
      await tester.pumpAndSettle();
      // De nep-adapter staat alles toe, dus alle drie de knoppen horen er.
      expect(find.text(l10n.d('Microfoon aanzetten')), findsOneWidget);
      expect(find.text(l10n.d('Camera aanzetten')), findsOneWidget);
      expect(find.text(l10n.d('Presentatie delen')), findsOneWidget);
    });

    testWidgets('een ingetrokken recht laat de knop verdwijnen zonder het '
        'gesprek te beëindigen', (tester) async {
      final container = await pump(tester, const MeetingWorkspaceDialog());
      const l10n = AppLocalizations(Locale('nl'));
      final session = await connect(container, 'direct');
      session.advanceAll();
      await tester.pumpAndSettle();
      expect(find.text(l10n.d('Presentatie delen')), findsOneWidget);

      // De organisator trekt het delen in — precies het geval uit §7.1.1.
      session.changeCapabilities(
        const MeetingCapabilities(
          canUseMicrophone: true,
          canUseCamera: true,
          canSeeRoster: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.d('Presentatie delen')), findsNothing);
      expect(
        container.read(meetingSessionProvider).phase,
        MeetingPhase.connected,
      );
      expect(find.text(l10n.d('Verlaten')), findsOneWidget);
    });

    testWidgets('de opname krijgt een blijvende banier (§15)', (tester) async {
      final container = await pump(tester, const MeetingWorkspaceDialog());
      const l10n = AppLocalizations(Locale('nl'));
      final session = await connect(container, 'endedByHost');
      // Het draaiboek meldt de opname vóór het einde; stap tot net daarna.
      for (var i = 0; i < 8; i++) {
        session.advance();
      }
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.d('Deze vergadering wordt opgenomen.')),
        findsOneWidget,
      );
    });

    testWidgets('de deelnemerslijst toont naam en rol', (tester) async {
      final container = await pump(tester, const MeetingWorkspaceDialog());
      final session = await connect(container, 'direct');
      session.advanceAll();
      await tester.pumpAndSettle();
      expect(find.textContaining('Deelnemers'), findsOneWidget);
      expect(find.text(fakeHostDisplayName), findsOneWidget);
      const l10n = AppLocalizations(Locale('nl'));
      expect(find.text(l10n.d('organisator')), findsOneWidget);
      expect(find.text(l10n.d('gast')), findsOneWidget);
    });

    testWidgets('na een mislukking staat de uitleg in het venster', (
      tester,
    ) async {
      final container = await pump(tester, const MeetingWorkspaceDialog());
      const l10n = AppLocalizations(Locale('nl'));
      final session = await connect(container, 'denied');
      session.advanceAll();
      await tester.pumpAndSettle();
      expect(
        find.text(meetingFailureText(l10n, MeetingFailureKind.lobbyDenied)),
        findsOneWidget,
      );
      expect(find.text(l10n.d('Afsluiten')), findsOneWidget);
    });
  });
}

/// Een knop die de deelnamedialoog opent — die dialoog hoort in een route te
/// staan, niet los in een Scaffold.
class _DialogHost extends StatelessWidget {
  const _DialogHost();

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => MeetingJoinDialog.show(context),
    child: const Text('Openen'),
  );
}
