part of 'privacy_scanner.dart';

// Publieke privacynamen blijven beschikbaar voor callers/tests; de waarden
// komen uit het ene documentveldcontract in document_front_matter.dart.
const int kMaxPrivacyDocumentFields = kMaxDocumentFields;
const int kMaxPrivacyDocumentFieldChars = kMaxDocumentFieldValueLength;

/// De scanner weigert documentmetadata die buiten de gedeelde invoergrenzen
/// valt. Stil afkappen zou juist het niet-gescande achterstuk laten uitlekken.
final class PrivacyDocumentLimitExceeded implements Exception {
  const PrivacyDocumentLimitExceeded(this.message);

  final String message;

  @override
  String toString() => 'PrivacyDocumentLimitExceeded: $message';
}

/// Alle velden die de scanner en daarmee de redactie langsloopt.
extension PrivacyScannerFragments on PrivacyScanner {
  /// De deckvelden die in de documentmetadata belanden (en dus meereizen in
  /// PDF-properties en PPTX-docProps, leesbaar, ook al staat er op geen enkele
  /// slide iets van te zien).
  Iterable<_Fragment> _deckFragments(Deck deck) sync* {
    yield* _validatedDocumentPrivacyFragments(deck);
    yield (field: 'deckTitle', index: 0, text: deck.title, context: '');
    yield (field: 'author', index: 0, text: deck.author, context: '');
    yield (
      field: 'organization',
      index: 0,
      text: deck.organization,
      context: '',
    );
    yield (field: 'description', index: 0, text: deck.description, context: '');
    yield (field: 'keywords', index: 0, text: deck.keywords, context: '');
    // Version en date zijn vrije tekstvelden uit hetzelfde dialoogvenster als de
    // vier hierboven en belanden in dezelfde front matter — ze vielen alleen
    // buiten deze lijst. "v1.2 — nagekeken door jan@klant.nl" ging daarmee
    // ongezien mee in elke export.
    yield (field: 'version', index: 0, text: deck.version, context: '');
    yield (field: 'date', index: 0, text: deck.date, context: '');
    yield* deckMarpPrivacyFragments(deck);
    for (var i = 0; i < deck.standardsUsed.length; i++) {
      yield (
        field: 'standardsUsed',
        index: i,
        text: deck.standardsUsed[i],
        context: '',
      );
    }
    for (var i = 0; i < deck.toolsUsed.length; i++) {
      yield (
        field: 'toolsUsed',
        index: i,
        text: deck.toolsUsed[i].name,
        context: '',
      );
    }
    // De MIAUW-motiveringen. Dit is de plek waar een naam het waarschijnlijkst
    // staat — "uitgesloten op verzoek van …" — en ze reizen base64-gecodeerd mee
    // in de front matter: onzichtbaar voor wie het bestand naleest, en dus ook
    // voor elk vangnet dat op platte tekst zoekt.
    var w = 0;
    for (final reason in deck.miauwWaivers.values) {
      yield (field: 'miauwWaivers', index: w++, text: reason, context: '');
    }
    var c = 0;
    for (final reason in deck.miauwConfirmations.values) {
      yield (
        field: 'miauwConfirmations',
        index: c++,
        text: reason,
        context: '',
      );
    }
  }

  /// Elk tekstdragend veld van een slide.
  ///
  /// `notes` staat er nadrukkelijk bij: sprekersnotities zijn onzichtbaar in de
  /// preview, maar gaan als platte tekst mee in de PPTX-notitiepagina's. Het is
  /// in de praktijk het vuilste veld van allemaal.
  Iterable<_Fragment> _slideFragments(Slide slide) sync* {
    final timelineContext = _timelineContextFor(slide);
    yield (field: 'title', index: 0, text: slide.title, context: '');
    yield (field: 'subtitle', index: 0, text: slide.subtitle, context: '');
    yield (
      field: 'columnTitle1',
      index: 0,
      text: slide.columnTitle1,
      context: '',
    );
    yield (
      field: 'columnTitle2',
      index: 0,
      text: slide.columnTitle2,
      context: '',
    );
    yield (
      field: 'imageCaption',
      index: 0,
      text: slide.imageCaption,
      context: '',
    );
    yield (
      field: 'imageCaption2',
      index: 0,
      text: slide.imageCaption2,
      context: '',
    );
    yield (
      field: 'imageAltText',
      index: 0,
      text: slide.imageAltText,
      context: '',
    );
    yield (
      field: 'imageAltText2',
      index: 0,
      text: slide.imageAltText2,
      context: '',
    );
    yield (field: 'quote', index: 0, text: slide.quote, context: '');
    yield (
      field: 'quoteAuthor',
      index: 0,
      text: slide.quoteAuthor,
      context: '',
    );
    yield (
      field: 'customMarkdown',
      index: 0,
      text: slide.customMarkdown,
      context: timelineContext ?? '',
    );
    yield (field: 'notes', index: 0, text: slide.notes, context: '');
    yield* slideMarpPrivacyFragments(slide);
    // Het scope-object van een checklist/bevinding: vrije tekst die als
    // `ocideck_checklist_scope` mee round-trippt. In pentestwerk staat daar
    // routineus een URL met een gebruikersnaam of tenant in.
    yield (
      field: 'checklistScope',
      index: 0,
      text: slide.checklistScope,
      context: '',
    );

    // De mediapaden. Een `/Users/jan.jansen/…` in een afbeeldingsverwijzing
    // verraadt gewoon een naam, en dat pad reist mee in de markdown en dus in de
    // HTML-export.
    //
    // De projectie lakt hier geen tekens in weg — een pad met blokjes erin is
    // een kapotte verwijzing, en de auteur hernoemt het bestand of verplaatst
    // het. Maar op een slide die op `redact` staat verdwijnt de hele
    // mediaverwijzing (zie `_projectMedia`), dus dáár komt het pad ook niet meer
    // in de export terecht. Dat was eerder wél zo, en dan reisde een
    // gedetecteerde `/Users/jan.jansen/…` gewoon mee.
    yield (field: 'imagePath', index: 0, text: slide.imagePath, context: '');
    yield (field: 'imagePath2', index: 0, text: slide.imagePath2, context: '');
    yield (field: 'videoPath', index: 0, text: slide.videoPath, context: '');
    yield (field: 'audioPath', index: 0, text: slide.audioPath, context: '');
    // Callout descriptions are ordinary scannable content (IMAGE_CALLOUTS.md
    // §8): an email or phone number in a description is a privacy finding,
    // just as it would be in a bullet. Geometry is excluded — the coordinates
    // are 3-decimal image-space values that the geo rule cannot flag.
    for (var i = 0; i < slide.callouts.length; i++) {
      yield (
        field: 'calloutDescription',
        index: i,
        text: slide.callouts[i].description,
        context: '',
      );
    }
    for (var i = 0; i < slide.bullets.length; i++) {
      yield (field: 'bullets', index: i, text: slide.bullets[i], context: '');
    }
    for (var i = 0; i < slide.bullets2.length; i++) {
      yield (field: 'bullets2', index: i, text: slide.bullets2[i], context: '');
    }
    // Tabelcellen krijgen een doorlopende index (rij * kolommen + kolom).
    // Eén vaste staplengte over álle rijen. Met `row.length` per rij was de
    // afbeelding geen bijectie zodra een tabel ongelijke rijen had — een legale
    // markdown-tabel — en botsten twee cellen op dezelfde sleutel: de ene
    // redactie landde dan op de andere cel, of viel buiten zijn tekst en gooide
    // een RangeError bij het presenteren of exporteren.
    if (timelineContext != null) return;
    final stride = slide.tableRows.fold<int>(
      0,
      (m, r) => r.length > m ? r.length : m,
    );
    for (var r = 0; r < slide.tableRows.length; r++) {
      final row = slide.tableRows[r];
      for (var c = 0; c < row.length; c++) {
        yield (
          field: 'tableRows',
          index: r * stride + c,
          text: row[c],
          // De kolomkop telt mee als omgeving: "BSN" bovenaan de kolom maakt de
          // nummers eronder herkenbaar, ook al staan ze in een ander fragment.
          context: r == 0 || slide.tableRows.first.length <= c
              ? ''
              : slide.tableRows.first[c],
        );
      }
    }
  }
}

void _checkPrimaryMetadataPrivacyLengths(Deck deck) {
  _checkDocumentPrivacyLength('titel', deck.title);
  _checkDocumentPrivacyLength('auteur', deck.author);
  _checkDocumentPrivacyLength('ondertitel', deck.description);
}

Iterable<_Fragment> _validatedDocumentPrivacyFragments(Deck deck) sync* {
  _checkPrimaryMetadataPrivacyLengths(deck);
  yield* _documentPrivacyFragments(deck);
}

Iterable<_Fragment> _documentPrivacyFragments(Deck deck) sync* {
  final fields = deck.documentFields;
  if (fields.length > kMaxDocumentFields) {
    throw PrivacyDocumentLimitExceeded(
      'document bevat ${fields.length} velden; maximaal '
      '$kMaxDocumentFields',
    );
  }
  for (final entry in fields.entries) {
    _checkDocumentPrivacyLength('veldsleutel ${entry.key}', entry.key);
    _checkDocumentPrivacyLength('documentveld ${entry.key}', entry.value);
  }
  final header = _resolvedDocumentChrome(
    deck,
    deck.themeProfile.documentHeaderText,
  );
  final footer = _resolvedDocumentChrome(
    deck,
    deck.themeProfile.documentFooterText,
  );
  _checkDocumentPrivacyLength('samengestelde documentkop', header);
  _checkDocumentPrivacyLength('samengestelde documentvoet', footer);
  yield (field: 'documentHeader', index: 0, text: header, context: '');
  yield (field: 'documentFooter', index: 0, text: footer, context: '');
  var index = 0;
  for (final entry in deck.documentFields.entries) {
    if (const {'title', 'subtitle', 'author'}.contains(entry.key)) continue;
    yield (
      field: 'documentFieldKeys',
      index: index,
      text: entry.key,
      context: '',
    );
    yield (
      field: 'documentFields',
      index: index,
      text: entry.value,
      context: entry.key,
    );
    index++;
  }
}

String _resolvedDocumentChrome(Deck deck, String template) =>
    resolveDocumentChromeTemplate(
      template,
      _documentChromeFields(deck),
      escapeMarkdownValues: false,
    );

Map<String, String> _documentChromeFields(Deck deck) => {
  ...deck.documentFields,
  'title': deck.title,
  'subtitle': deck.description,
  'author': deck.author,
};

void _checkDocumentPrivacyLength(String label, String value) {
  if (value.length <= kMaxDocumentFieldValueLength) return;
  throw PrivacyDocumentLimitExceeded(
    '$label bevat ${value.length} tekens; maximaal '
    '$kMaxDocumentFieldValueLength',
  );
}

_TimelineContextIndex? _timelineContextFor(Slide slide) =>
    startsWithDocumentTimelineEnvelope(slide.customMarkdown)
    ? _TimelineContextIndex.parse(slide.customMarkdown)
    : null;
