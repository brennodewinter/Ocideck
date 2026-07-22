import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

/// De exportbundel-fabriek. Stond tot #613 als closure in de layout-state en
/// was daardoor alleen via een widgettest te bereiken; nu hij in `services`
/// staat, is hij gewoon een functie met invoer en uitvoer.
///
/// Wat hier bewaakt wordt is de projectiegrens: het dialoog krijgt deze bundel
/// en niets anders, dus alles wat een ontvanger niet mag zien moet er hier al
/// uit zijn — in de dia's, in de markdown voor de HTML-export, en geteld in de
/// samenvatting waar de exportpoort op afgaat.
void main() {
  Deck deckMet(String bullet, {PrivacyDisposition? privacy}) => Deck(
    title: 'Rapport',
    slides: [
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Contact', bullets: [bullet], privacy: privacy),
    ],
  );

  ExportBundle bundleVan(
    Deck deck, {
    PrivacyExportProfile profile = PrivacyExportProfile.full,
    bool includeDetail = true,
  }) => buildExportBundle(
    deck,
    deck.slides,
    profile: profile,
    includeDetail: includeDetail,
    disabledRules: const {},
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    markdownService: MarkdownService(),
  );

  test('een dia op redact komt geredigeerd de bundel uit', () {
    final bundle = bundleVan(
      deckMet('Bel 06-12345678', privacy: PrivacyDisposition.redact),
    );
    expect(
      bundle.audience.deck.slides.single.bullets.single,
      isNot(contains('12345678')),
    );
  });

  test(
    'de markdown voor de HTML-export komt uit hetzelfde geprojecteerde deck',
    () {
      // Anders zou de HTML-export het origineel dragen terwijl de PDF geredigeerd
      // is — dezelfde bundel, twee verschillende waarheden.
      final bundle = bundleVan(
        deckMet('Bel 06-12345678', privacy: PrivacyDisposition.redact),
      );
      expect(bundle.markdown, isNot(contains('12345678')));
    },
  );

  test('zonder redactie blijft de tekst staan', () {
    final bundle = bundleVan(
      deckMet('Bel 06-12345678', privacy: PrivacyDisposition.accept),
    );
    expect(
      bundle.audience.deck.slides.single.bullets.single,
      contains('12345678'),
    );
  });

  test('de samenvatting hoort bij de bundel', () {
    // Meer dan "hij bestaat" staat hier bewust niet: de telling slaat alleen aan
    // op bevindingen met zekerheid `certain`, en welke regels dat zijn hoort in
    // de scannertests thuis, niet hier. Wat déze fabriek moet waarmaken is dat
    // de samenvatting uit dezelfde scan komt als de projectie ernaast.
    expect(bundleVan(deckMet('Gewone tekst')).privacySummary.isEmpty, isTrue);
  });

  test('de beknopte versie laat de verdiepingsdia weg', () {
    final deck = Deck(
      title: 'Rapport',
      slides: [
        Slide.create(SlideType.bullets).copyWith(title: 'Hoofdlijn'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Verdieping', isDetail: true),
      ],
    );
    expect(bundleVan(deck).audience.deck.slides, hasLength(2));
    expect(
      bundleVan(deck, includeDetail: false).audience.deck.slides,
      hasLength(1),
    );
  });

  test('het geredigeerde profiel negeert de dispositie van de auteur', () {
    // "Deze zaal mag het zien" is niet hetzelfde als "iedereen mag het zien".
    final bundle = bundleVan(
      deckMet('Bel 06-12345678', privacy: PrivacyDisposition.accept),
      profile: PrivacyExportProfile.redacted,
    );
    expect(
      bundle.audience.deck.slides.single.bullets.single,
      isNot(contains('12345678')),
    );
  });

  test('het manifest beschrijft wat eruit ging', () {
    final bundle = bundleVan(
      deckMet('Bel 06-12345678', privacy: PrivacyDisposition.redact),
    );
    expect(bundle.manifest.entries, isNotEmpty);
    // Geen waarden in het manifest — dat is het hele punt ervan.
    expect(bundle.manifest.toPrettyJson(), isNot(contains('12345678')));
  });
}
