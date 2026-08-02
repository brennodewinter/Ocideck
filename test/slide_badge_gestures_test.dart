// De twee gebaren op een badge.
//
// Enkele klik opent het lijstje meldingen — de veilige actie, en dus de
// makkelijkste. Dubbelklik beslist: op een gekleurde badge accepteer je, op een
// grijze draai je terug. Dat het twee kanten op werkt is het punt; een
// beslissing die je niet met hetzelfde gebaar kunt terugnemen, durf je niet te
// nemen.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/quality_disposition.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

/// Een geldig, niet-voorbeeld NL-IBAN (mod-97 klopt) — levert een zekere
/// bevinding op.
const _iban = 'Rekening NL18RABO0123459876';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pumpThumbnail(
    WidgetTester tester, {
    required String bullet,
    PrivacyDisposition? privacy,
    QualityDisposition quality = QualityDisposition.warn,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    final slide = container.read(deckProvider).deck!.slides.single;
    notifier.updateSlide(
      0,
      slide.copyWith(bullets: [bullet], privacy: privacy, quality: quality),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 260,
              child: SlideThumbnail(
                slide: container.read(deckProvider).deck!.slides.single,
                index: 0,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Eén klik, met het dubbelklik-venster erna uitgezeten.
  ///
  /// Een GestureDetector met zowel onTap als onDoubleTap wacht na de eerste tik
  /// af of er een tweede komt. Zonder deze pump vuurt onTap dus nooit, en meet
  /// de test iets anders dan de gebruiker doet.
  Future<void> singleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  PrivacyDisposition privacyOf(ProviderContainer c) =>
      effectivePrivacyDisposition(
        deck: c.read(deckProvider).deck!.privacy,
        slide: c.read(deckProvider).deck!.slides.single.privacy,
      );

  testWidgets('enkele klik opent de meldingen van die slide', (tester) async {
    final container = await pumpThumbnail(tester, bullet: _iban);

    await singleTap(tester, find.byTooltip('Persoonsgegevens gevonden'));

    // De regel staat er, met het veld waar ze zit — dat is precies wat een
    // badge zonder popover níét vertelde.
    expect(find.textContaining('bankrekeningnummer'), findsOneWidget);
    expect(find.text('Opsomming'), findsOneWidget);
    // En de slide is nog niet aangeraakt: kijken is geen beslissen.
    expect(privacyOf(container), PrivacyDisposition.warn);
  });

  testWidgets('dubbelklik op een gekleurde badge accepteert', (tester) async {
    final container = await pumpThumbnail(tester, bullet: _iban);

    await doubleTap(tester, find.byTooltip('Persoonsgegevens gevonden'));

    expect(privacyOf(container), PrivacyDisposition.accept);
  });

  testWidgets('dubbelklik op een grijze badge draait de acceptatie terug', (
    tester,
  ) async {
    final container = await pumpThumbnail(
      tester,
      bullet: _iban,
      privacy: PrivacyDisposition.accept,
    );

    await doubleTap(tester, find.byTooltip('Persoonsgegevens geaccepteerd'));

    expect(privacyOf(container), PrivacyDisposition.warn);
  });

  testWidgets('dubbelklik laat redactie met rust', (tester) async {
    // Redactie terugdraaien zet zwart gelakte persoonsgegevens weer in de
    // export. Dat mag geen bijwerking van een dubbelklik zijn — die keuze hoort
    // in het instellingenpaneel, waar je ziet wat je kiest.
    final container = await pumpThumbnail(
      tester,
      bullet: _iban,
      privacy: PrivacyDisposition.redact,
    );

    // Een weggelaten dia heet ook "weggelaten", niet "geaccepteerd": zie de
    // groep hieronder. De grijze badge staat er, dubbelklikken doet er niets.
    await doubleTap(tester, find.byTooltip('Persoonsgegevens weggelaten'));

    expect(privacyOf(container), PrivacyDisposition.redact);
  });

  testWidgets('de kwaliteitsbadge accepteert los van privacy', (tester) async {
    // Twee badges, twee beslissingen. Een slide met te veel bullets accepteren
    // mag niets zeggen over de persoonsgegevens erop.
    final container = await pumpThumbnail(
      tester,
      bullet: _iban,
      quality: QualityDisposition.accept,
    );

    expect(
      container.read(deckProvider).deck!.slides.single.quality,
      QualityDisposition.accept,
    );
    expect(privacyOf(container), PrivacyDisposition.warn);
  });

  // #1112: de grijze badge dekt drie standen af (accepteren, waarschuwen,
  // weglaten). Vroeger zei hij op alle drie "geaccepteerd" — onwaar voor een
  // weggelaten dia, waar niets is geaccepteerd. Elke stand hoort zijn eigen woord.
  group('de badge noemt de wérkelijke privacy-stand', () {
    testWidgets('accepteren → geaccepteerd', (tester) async {
      await pumpThumbnail(
        tester,
        bullet: _iban,
        privacy: PrivacyDisposition.accept,
      );
      expect(find.byTooltip('Persoonsgegevens geaccepteerd'), findsOneWidget);
    });

    testWidgets('waarschuwen → gemarkeerd voor de ontvanger', (tester) async {
      await pumpThumbnail(
        tester,
        bullet: _iban,
        privacy: PrivacyDisposition.shield,
      );
      expect(
        find.byTooltip('Persoonsgegevens gemarkeerd voor de ontvanger'),
        findsOneWidget,
      );
      expect(find.byTooltip('Persoonsgegevens geaccepteerd'), findsNothing);
    });

    testWidgets('weglaten → weggelaten, níét geaccepteerd', (tester) async {
      await pumpThumbnail(
        tester,
        bullet: _iban,
        privacy: PrivacyDisposition.redact,
      );
      expect(find.byTooltip('Persoonsgegevens weggelaten'), findsOneWidget);
      // De kern van de bug: een weggelaten dia zei "geaccepteerd".
      expect(find.byTooltip('Persoonsgegevens geaccepteerd'), findsNothing);
    });

    testWidgets('nog niet beslist → gevonden', (tester) async {
      await pumpThumbnail(tester, bullet: _iban);
      expect(find.byTooltip('Persoonsgegevens gevonden'), findsOneWidget);
    });
  });
}
