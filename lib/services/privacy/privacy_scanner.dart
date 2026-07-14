// De privacyscanner: leest een deck na op gegevens die privacygevoelig kunnen
// zijn.
//
// Twee dingen sturen het ontwerp:
//
// 1. Vals-positieven zijn duurder dan vals-negatieven. Een scanner die bij elk
//    ordernummer "BSN!" roept, wordt uitgezet — en detecteert daarna niets meer.
//    Vandaar checksums (privacy_checksums.dart), een registry van nepwaarden
//    (privacy_allowlist.dart) en contextpoorten waar de checksum te zwak is.
//
// 2. De scanner is een hulpmiddel, geen garantie. Hij vindt geen tekst in
//    afbeeldingen, geen gegevens in gelinkte bestanden, en geen gevoelige
//    informatie zonder herkenbaar patroon. Een slide zonder meldingen is een
//    slide waarin WIJ niets hebben gevonden.
//
// De scan is puur en synchroon: dezelfde slide geeft altijd dezelfde bevindingen.

import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import 'privacy_allowlist.dart';
import 'privacy_checksums.dart';

/// Eén tekstfragment van een slide, met de veldnaam waar het uit komt.
typedef _Fragment = ({String field, int index, String text});

/// Hoe ver een contextwoord vóór een treffer mag staan om nog te tellen.
///
/// Ruim genoeg voor "Het burgerservicenummer van betrokkene is 123456782", krap
/// genoeg dat een woord elders in de zin niet meetelt.
const int kContextWindow = 40;

/// Contextwoorden die van een 11-proef-treffer een echte BSN-melding maken.
/// Zonder een van deze blijft de treffer informatief — zie [_scanBsn].
const List<String> bsnContextWords = [
  'bsn',
  'burgerservicenummer',
  'burgerservice',
  'sofinummer',
  'sofi-nummer',
  'sofinr',
];

final _reEmail = RegExp(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}");

/// Een IBAN staat vaak met spaties in een tekst. We accepteren die en
/// normaliseren pas in de validatie.
final _reIban = RegExp(r'\b[A-Z]{2}\d{2}(?:[ -]?[A-Z0-9]){10,30}\b');

/// Negen losstaande cijfers. Bewust ruim: de 11-proef en de contextpoort doen
/// het filterwerk, niet de regex.
final _reNineDigits = RegExp(r'(?<!\d)\d{9}(?!\d)');

/// Leest een deck na op privacygevoelige gegevens.
class PrivacyScanner {
  const PrivacyScanner();

  /// Scant het hele deck. Deckbrede velden (titel, auteur, trefwoorden) krijgen
  /// [kDeckWidePrivacyIndex].
  PrivacyScanResult scan(Deck deck) {
    final findings = <PrivacyFinding>[];

    for (final fragment in _deckFragments(deck)) {
      _scanFragment(fragment, kDeckWidePrivacyIndex, findings);
    }
    for (var i = 0; i < deck.slides.length; i++) {
      for (final fragment in _slideFragments(deck.slides[i])) {
        _scanFragment(fragment, i, findings);
      }
    }
    return PrivacyScanResult(findings);
  }

  /// Scant één slide los — voor de per-slide memoisatie in de provider.
  PrivacyScanResult scanSlide(Slide slide, int index) {
    final findings = <PrivacyFinding>[];
    for (final fragment in _slideFragments(slide)) {
      _scanFragment(fragment, index, findings);
    }
    return PrivacyScanResult(findings);
  }

  void _scanFragment(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    if (fragment.text.isEmpty) return;
    _scanEmail(fragment, slideIndex, out);
    _scanIban(fragment, slideIndex, out);
    _scanBsn(fragment, slideIndex, out);
  }

  // ── contact.email ─────────────────────────────────────────────────────────

  void _scanEmail(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    if (!fragment.text.contains('@')) return;
    for (final match in _reEmail.allMatches(fragment.text)) {
      final address = match.group(0)!;
      if (isPlaceholderEmail(address)) continue;
      out.add(
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.email',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
  }

  // ── fin.iban ──────────────────────────────────────────────────────────────

  void _scanIban(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    for (final match in _reIban.allMatches(fragment.text)) {
      final candidate = match.group(0)!;
      if (!isValidIban(candidate)) continue;
      if (isExampleIban(candidate)) continue;
      out.add(
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'fin.iban',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
  }

  // ── nl.bsn ────────────────────────────────────────────────────────────────

  /// Een BSN-treffer is pas een waarschuwing als er óók context is.
  ///
  /// De 11-proef laat ongeveer één op de elf willekeurige 9-cijferige getallen
  /// door (vastgelegd in `privacy_checksums_test.dart`). Zouden we daarop alleen
  /// afgaan, dan vuurt de scanner op elk elfde ordernummer, factuurnummer en
  /// klantnummer — en dan zet de gebruiker hem uit. Dus:
  ///
  ///   * checksum + contextwoord  → `certain`, een echte melding;
  ///   * checksum zonder context  → `possible`, informatief.
  ///
  /// Testnummers en betekenisloze reeksen vallen sowieso af.
  void _scanBsn(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    for (final match in _reNineDigits.allMatches(fragment.text)) {
      final digits = match.group(0)!;
      if (!passesElevenProof(digits)) continue;
      if (isNonPersonalBsn(digits)) continue;

      final hasContext = _hasContextWord(
        fragment.text,
        match.start,
        bsnContextWords,
      );
      out.add(
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'nl.bsn',
          family: PrivacyFamily.identifier,
          confidence: hasContext
              ? PrivacyConfidence.certain
              : PrivacyConfidence.possible,
        ),
      );
    }
  }

  /// Staat een van [words] binnen [kContextWindow] tekens vóór de treffer?
  bool _hasContextWord(String text, int matchStart, List<String> words) {
    final from = (matchStart - kContextWindow).clamp(0, text.length);
    final window = text.substring(from, matchStart).toLowerCase();
    return words.any(window.contains);
  }

  PrivacyFinding _finding(
    _Fragment fragment,
    int slideIndex,
    Match match, {
    required String ruleId,
    required PrivacyFamily family,
    required PrivacyConfidence confidence,
  }) {
    return PrivacyFinding(
      ruleId: ruleId,
      family: family,
      confidence: confidence,
      slideIndex: slideIndex,
      field: fragment.field,
      fragmentIndex: fragment.index,
      start: match.start,
      end: match.end,
      // Nooit de volledige waarde: een privacycontrole die de gevonden BSN's
      // in haar eigen meldingen zet, heeft het probleem verplaatst.
      maskedSample: maskValue(match.group(0)!),
    );
  }

  // ── Welke velden gescand worden ───────────────────────────────────────────

  /// De deckvelden die in de documentmetadata belanden (en dus meereizen in
  /// PDF-properties en PPTX-docProps, leesbaar, ook al staat er op geen enkele
  /// slide iets van te zien).
  Iterable<_Fragment> _deckFragments(Deck deck) sync* {
    yield (field: 'deckTitle', index: 0, text: deck.title);
    yield (field: 'author', index: 0, text: deck.author);
    yield (field: 'organization', index: 0, text: deck.organization);
    yield (field: 'description', index: 0, text: deck.description);
    yield (field: 'keywords', index: 0, text: deck.keywords);
  }

  /// Elk tekstdragend veld van een slide.
  ///
  /// `notes` staat er nadrukkelijk bij: sprekersnotities zijn onzichtbaar in de
  /// preview, maar gaan als platte tekst mee in de PPTX-notitiepagina's. Het is
  /// in de praktijk het vuilste veld van allemaal.
  Iterable<_Fragment> _slideFragments(Slide slide) sync* {
    yield (field: 'title', index: 0, text: slide.title);
    yield (field: 'subtitle', index: 0, text: slide.subtitle);
    yield (field: 'columnTitle1', index: 0, text: slide.columnTitle1);
    yield (field: 'columnTitle2', index: 0, text: slide.columnTitle2);
    yield (field: 'imageCaption', index: 0, text: slide.imageCaption);
    yield (field: 'imageCaption2', index: 0, text: slide.imageCaption2);
    yield (field: 'imageAltText', index: 0, text: slide.imageAltText);
    yield (field: 'imageAltText2', index: 0, text: slide.imageAltText2);
    yield (field: 'quote', index: 0, text: slide.quote);
    yield (field: 'quoteAuthor', index: 0, text: slide.quoteAuthor);
    yield (field: 'customMarkdown', index: 0, text: slide.customMarkdown);
    yield (field: 'notes', index: 0, text: slide.notes);

    for (var i = 0; i < slide.bullets.length; i++) {
      yield (field: 'bullets', index: i, text: slide.bullets[i]);
    }
    for (var i = 0; i < slide.bullets2.length; i++) {
      yield (field: 'bullets2', index: i, text: slide.bullets2[i]);
    }
    // Tabelcellen krijgen een doorlopende index (rij * kolommen + kolom), zodat
    // één int volstaat om de cel terug te vinden.
    for (var r = 0; r < slide.tableRows.length; r++) {
      final row = slide.tableRows[r];
      for (var c = 0; c < row.length; c++) {
        yield (field: 'tableRows', index: r * row.length + c, text: row[c]);
      }
    }
  }
}
