import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/presentation_step_plan.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

/// De onthulstap moet worden *aangekondigd* (IMAGE_CALLOUTS.md §12.2). Zonder
/// aankondiging ziet een schermlezer-gebruiker de bullet verschijnen zonder er
/// iets van te merken: de dia verandert, de focus niet.
///
/// Dit is de Flutter-tegenhanger van de `aria-live`-region uit §12.2. De
/// HTML-export stapt niet en heeft er dus geen — hier gebeurt het wel, en
/// daarom wordt het hier getoetst.

Slide _revealSlide() => const Slide(
  id: 'onthullen',
  anchor: 'onthullen',
  type: SlideType.bulletsImage,
  title: 'Stap voor stap',
  bullets: [
    'Het water komt hier binnen (A)',
    'Hier wordt de druk gemeten (B)',
    'Deze regel heeft geen verwijzing',
  ],
  imagePath: 'beeld.png',
  calloutReveal: BulletRevealMode.steps,
  callouts: [
    ImageCallout(
      reference: 'A',
      targets: [CalloutPoint(0.25, 0.34)],
      description: 'de aanvoerklep links',
    ),
    ImageCallout(
      reference: 'B',
      targets: [CalloutPoint(0.69, 0.60), CalloutPoint(0.70, 0.30)],
      description: 'de meetkamer',
    ),
  ],
);

Widget _host(List<Slide> slides) => MaterialApp(
  localizationsDelegates: const [
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: FullscreenPresenter(
    slides: slides,
    projectPath: null,
    themeProfile: const ThemeProfile(),
    initialIndex: 0,
  ),
);

void main() {
  testWidgets('elke onthulstap meldt wat er bij die stap bij kwam', (
    tester,
  ) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (dynamic message) async {
        final map = message as Map<Object?, Object?>;
        if (map['type'] == 'announce') {
          final data = map['data'] as Map<Object?, Object?>;
          announced.add(data['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await tester.pumpWidget(_host([_revealSlide()]));
    await tester.pumpAndSettle();
    announced.clear(); // de dia-aankondiging bij binnenkomst telt hier niet

    Future<void> next() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    // Stap 1: bullet A met één target. Enkelvoud, want het is er één.
    await next();
    expect(
      announced,
      isNotEmpty,
      reason: 'de eerste onthulstap hoort te worden aangekondigd',
    );
    expect(announced.last, 'Punt 1/3, 1 markering');

    // Stap 2: bullet B brengt twéé targets mee. Het getal telt de markeringen
    // die verschijnen, niet de verwijzingen die inmiddels staan.
    await next();
    expect(announced.last, 'Punt 2/3, 2 markeringen');

    // Stap 3: een bullet zonder verwijzing. Er komt niets bij, dus er wordt
    // ook niets over markeringen gemeld — vroeger herhaalde deze stap het
    // totaal van de vorige.
    await next();
    expect(announced.last, 'Punt 3/3');
  });

  group('stepAnnouncement — de bewoording, zonder presenter', () {
    const l10n = AppLocalizations(Locale('nl'));

    test('een tijdlijnstap meldt het gebeurtenisnummer', () {
      const plan = TimelineStepPlan(eventCount: 4);
      // Stap 0 toont al de eerste gebeurtenis: stap 2 is de derde.
      expect(stepAnnouncement(plan, 2, l10n), 'Gebeurtenis 3/4');
    });

    test('geen stapplan: niets te melden', () {
      expect(stepAnnouncement(null, 1, l10n), isNull);
    });

    test('een verwijzing met twee targets telt er twee', () {
      final plan = CalloutRevealStepPlan.forSlide(_revealSlide());
      expect(stepAnnouncement(plan, 1, l10n), 'Punt 1/3, 1 markering');
      expect(stepAnnouncement(plan, 2, l10n), 'Punt 2/3, 2 markeringen');
      expect(stepAnnouncement(plan, 3, l10n), 'Punt 3/3');
    });
  });
}
