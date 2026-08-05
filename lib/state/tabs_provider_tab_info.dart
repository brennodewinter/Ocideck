// Part of the tabs_provider library — see tabs_provider.dart.
// [TabInfo] en [TabsState]: wat één tabblad is en wat de verzameling tabbladen
// is. Losgetrokken zodat tabs_provider.dart onder de groottegrens blijft; het
// zijn de twee datatypes waar de rest van dat bestand op werkt, dus ze horen
// bij elkaar en nergens anders.
part of 'tabs_provider.dart';

// ── Per-tab data ──────────────────────────────────────────────────────────────

/// De inhoud van een tabblad: óf een presentatie (deck) óf een document.
///
/// Sealed zodat elke plek die beide soorten moet behandelen dat expliciet en
/// exhaustief doet — de naad uit docs/design/DOCUMENT_MODE.md §2, waar deck en
/// document één substraat (opslag, herstel, dirty) delen zónder dat het
/// deck-model aan doorlopende tekst wordt opgedrongen. De gedeelde tab-velden
/// (id, herkomst, samenwerksessie) blijven op [TabInfo]; alleen de notifier(s)
/// verschillen per soort.
sealed class TabContent {
  const TabContent();

  MarkdownKind get kind;
}

/// Een presentatietabblad: het zware [DeckNotifier] (deck + ongedaan-historie)
/// plus de lichte [EditorNotifier] voor de per-dia editor.
class DeckTabContent extends TabContent {
  const DeckTabContent(this.deckNotifier, this.editorNotifier);

  final DeckNotifier deckNotifier;
  final EditorNotifier editorNotifier;

  @override
  MarkdownKind get kind => MarkdownKind.presentation;
}

/// Een documenttabblad: één [DocumentNotifier] over het platte `.md`. Geen
/// per-dia editor — een document is de bron zelf.
class DocumentTabContent extends TabContent {
  const DocumentTabContent(this.documentNotifier);

  final DocumentNotifier documentNotifier;

  @override
  MarkdownKind get kind => MarkdownKind.document;
}

class TabInfo {
  final int id;

  /// Stabiele sleutel voor het autosave-herstelbestand van dit tabblad.
  final String recoveryId;

  /// Wat dit tabblad bewerkt — een deck of een document. De rest van de
  /// tab-laag leest [content] (of de compat-getters hieronder).
  final TabContent content;

  /// Waar het deck in dit tabblad vandaan kwam, of `null` voor een nieuw of
  /// puur lokaal deck. Muteerbaar: wordt na het openen ingevuld en bij elke
  /// `state`-kopie hergebruikt.
  ///
  /// Eén veld, geen drie. Vroeger droeg een tabblad een `webdavOrigin`, een
  /// `s3Origin` en een `gitOrigin` naast elkaar met een opmerking erbij dat een
  /// deck er hooguit één zou hebben — maar niets handhaafde dat, dus een deck
  /// dat van WebDAV kwam en naar S3 werd weggeschreven droeg er twee. Sinds
  /// opslaan de herkomst volgt, moet die vraag één antwoord hebben.
  StorageOrigin? origin;

  /// De herkomst als die van WebDAV komt, anders `null`. De backends werken met
  /// hun eigen type; deze accessors houden dat leesbaar zonder het ene veld op
  /// te geven. Iets toekennen vervangt een herkomst van een andere soort — dat
  /// is precies de bedoeling: het deck komt nu daarvandaan.
  WebdavOrigin? get webdavOrigin {
    final o = origin;
    return o is WebdavOrigin ? o : null;
  }

  set webdavOrigin(WebdavOrigin? value) {
    if (value != null || origin is WebdavOrigin) origin = value;
  }

  /// De herkomst als die uit een git-repository komt, anders `null`. Draagt
  /// naast de repo ook de `baseSha` waartegen dit werk is geschreven — dát is
  /// wat versiebeheer toevoegt boven de andere twee.
  GitOrigin? get gitOrigin {
    final o = origin;
    return o is GitOrigin ? o : null;
  }

  set gitOrigin(GitOrigin? value) {
    if (value != null || origin is GitOrigin) origin = value;
  }

  /// De herkomst als die uit een S3-bucket komt, anders `null`.
  S3Origin? get s3Origin {
    final o = origin;
    return o is S3Origin ? o : null;
  }

  set s3Origin(S3Origin? value) {
    if (value != null || origin is S3Origin) origin = value;
  }

  /// De actieve samenwerksessie van dit tabblad, of `null` wanneer het niet
  /// samenwerkt — wat elk tabblad vandaag is (COLLABORATION.md §5.7: "Store the
  /// active SessionRef on TabInfo"). De transportloze samenwerklaag onder
  /// `lib/collab/` staat op zichzelf; dit veld is de naad waar een genetwerkte
  /// fase (Matrix, §6) de live sessie aan een tabblad hangt. Muteerbaar zoals
  /// [origin]: na het starten ingevuld, bij het einde weer op `null`.
  CollabSession? collabSession;

  TabInfo({
    required this.id,
    required this.recoveryId,
    required this.content,
    this.origin,
  });

  /// Presentatie of document.
  MarkdownKind get kind => content.kind;

  /// Compat: de deck-notifier van dit tabblad. Gooit voor een documenttabblad —
  /// deck-only paden (dia's, git, S3, import) horen zo'n tab nooit te bereiken;
  /// de schil verbergt hun acties per soort. Soort-bewuste code leest [content],
  /// [documentNotifier] of [kind] in plaats van deze getter.
  DeckNotifier get deckNotifier => switch (content) {
    DeckTabContent(:final deckNotifier) => deckNotifier,
    DocumentTabContent() => throw StateError(
      'deckNotifier opgevraagd op een documenttabblad',
    ),
  };

  /// Compat, als [deckNotifier]: de per-dia editor-notifier. Documenttabbladen
  /// hebben er geen (een document is de bron zelf), dus dit gooit voor zo'n tab.
  EditorNotifier get editorNotifier => switch (content) {
    DeckTabContent(:final editorNotifier) => editorNotifier,
    DocumentTabContent() => throw StateError(
      'editorNotifier opgevraagd op een documenttabblad',
    ),
  };

  /// De document-notifier van dit tabblad, of `null` voor een presentatie.
  DocumentNotifier? get documentNotifier => switch (content) {
    DocumentTabContent(:final documentNotifier) => documentNotifier,
    DeckTabContent() => null,
  };

  String get label => switch (content) {
    DeckTabContent(:final deckNotifier) => _deckTabLabel(deckNotifier),
    DocumentTabContent(:final documentNotifier) => _documentTabLabel(
      documentNotifier,
    ),
  };

  bool get isDirty => switch (content) {
    DeckTabContent(:final deckNotifier, :final editorNotifier) =>
      deckNotifier.mounted &&
          (deckNotifier.currentState.isDirty ||
              editorNotifier.currentState.hasMarkdownDraft),
    DocumentTabContent(:final documentNotifier) =>
      documentNotifier.mounted && documentNotifier.currentState.isDirty,
  };

  bool get isOpen => switch (content) {
    DeckTabContent(:final deckNotifier) =>
      deckNotifier.mounted && deckNotifier.currentState.isOpen,
    DocumentTabContent(:final documentNotifier) =>
      documentNotifier.mounted && documentNotifier.currentState.isOpen,
  };
}

/// Het opschrift van een presentatietabblad.
///
/// Rond het sluiten van een tab of het venster kan Riverpod de notifier al
/// hebben opgeruimd (de ProviderScope van de tab is dan ontmanteld) terwijl het
/// [TabInfo] nog één rebuild lang in beeld is. Lezen van een gedisposede
/// StateNotifier gooit; val dan terug op de neutrale [_newTabLabel]. Die volgt
/// de actieve taal en is geen kale literal — het is het eerste woord linksboven
/// in het venster (#576/#1251).
String _deckTabLabel(DeckNotifier deckNotifier) {
  if (!deckNotifier.mounted) return _newTabLabel;
  final st = deckNotifier.currentState;
  // A saved deck is identified by its file name — that is what the user
  // recognises, not the parsed first-slide title (which falls back to the
  // generic 'Presentatie').
  final path = st.filePath;
  if (path != null && path.isNotEmpty) {
    final name = p.basenameWithoutExtension(path);
    if (name.isNotEmpty) return name;
  }
  final deck = st.deck;
  return deck?.title.isNotEmpty == true ? deck!.title : _newTabLabel;
}

/// Het opschrift van een documenttabblad: de bestandsnaam, of [_newTabLabel]
/// zolang het document niet is opgeslagen (zelfde neutrale val als een deck).
String _documentTabLabel(DocumentNotifier documentNotifier) {
  if (!documentNotifier.mounted) return _newTabLabel;
  final path = documentNotifier.currentState.filePath;
  if (path != null && path.isNotEmpty) {
    final name = p.basenameWithoutExtension(path);
    if (name.isNotEmpty) return name;
  }
  return _newTabLabel;
}

// ── Tabs state ────────────────────────────────────────────────────────────────

class TabsState {
  final List<TabInfo> tabs;
  final int selectedIndex;

  const TabsState({required this.tabs, this.selectedIndex = 0});

  int get clampedIndex => selectedIndex.clamp(
    0,
    (tabs.length - 1).clamp(0, double.maxFinite.toInt()),
  );

  TabInfo? get current => tabs.isEmpty ? null : tabs[clampedIndex];

  bool get anyDirty => tabs.any((t) => t.isDirty);

  TabsState copyWith({List<TabInfo>? tabs, int? selectedIndex}) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }
}

/// Het opschrift van een tabblad zonder deck. Volgt de actieve interfacetaal
/// via [AppLocalizations.active] — niet de kale literal `'Nieuw'` die in alle
/// 32 talen Nederlands gaf (#576), en niet `const AppLocalizations(Locale('nl'))`,
/// waarvan de `Locale('nl')` een misleidend handvat is (#1251).
String get _newTabLabel => AppLocalizations.active.d('Nieuw');
