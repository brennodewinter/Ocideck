import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/chart.dart';
import '../models/markdown_kind.dart';
import '../models/markdown_outline.dart';
import '../models/privacy_disposition.dart';
import '../models/slide.dart';
import '../services/caption_service.dart';
import '../services/description_service.dart';
import '../services/document_deck_bridge.dart';
import '../services/document_export_service.dart';
import '../services/export_bundle.dart';
import '../services/export_metadata.dart';
import '../services/file_service.dart';
import '../services/html_image_embedder.dart';
import '../services/image_service.dart' show ImageImportFailure;
import '../services/markdown_table_codec.dart';
import '../services/marp_html_service.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../platform/platform_features.dart';
import '../state/deck_provider.dart'
    show fileServiceProvider, imageServiceProvider, markdownServiceProvider;
import '../state/document_provider.dart';
import '../state/settings_provider.dart' show settingsProvider, SettingsTraces;
import '../state/tabs_provider.dart';
import '../theme/app_theme.dart';
import '../utils/doc_link.dart' show headingSlug;
import '../utils/error_snackbar.dart';
import '../utils/image_search_paths.dart';
import '../utils/log.dart';
import '../utils/markdown_blocks.dart';
import '../utils/markdown_paste_cleanup.dart';
import '../utils/table_clipboard.dart';
import '../utils/user_facing_error.dart';
import 'dialogs/convert_to_presentation_dialog.dart';
import 'dialogs/document_export_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/package_encrypt_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'editors/_editor_field.dart' show reportImageImportFailure;
import 'editors/chart_editor.dart';
import 'editors/table_editor.dart';
import 'markdown_editor/markdown_editor.dart';
import 'reader/document_markdown_view.dart';

/// De schermvullende editor voor een documenttabblad: links de platte
/// Markdown-bron, rechts een live weergave. De bron *ís* de waarheid — elke
/// toetsaanslag stroomt direct naar de [DocumentNotifier] (geen 'Toepassen'-muur,
/// DOCUMENT_MODE.md §1.1), en de weergave hertekent mee.
///
/// Bewust nog kaal: dit is de rauw+preview-basis. De visuele (WYSIWYG) modus met
/// ingebedde kaarten, het invoeg-palet en de Overzicht-rail komen er in latere
/// fasen omheen — dit oppervlak is de spil waar ze op landen.
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key});

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late final TextEditingController _controller;
  final ScrollController _previewScroll = ScrollController();

  /// De kop waar de Overzicht-rail naartoe scrollt: het blokindexnummer in de
  /// weergave dat [_anchorKey] draagt, of -1. Dezelfde één-verplaatsende-sleutel
  /// als de docs-lezer, zodat `ensureVisible` betrouwbaar landt.
  final GlobalKey _anchorKey = GlobalKey();
  int _anchorBlockIndex = -1;

  /// Actieve kop in de Overzicht-rail (−1 = geen), afgeleid van de caret.
  int _activeOutlineIndex = -1;

  /// Of de Overzicht-rail is ingeklapt tot een smalle strook.
  bool _outlineCollapsed = false;

  /// Signaal + doel voor springen in de visuele [MarkdownNotesEditor].
  int _revealSignal = 0;
  int? _revealMarkdownOffset;
  String? _revealTitle;

  /// De actieve weergavemodus. [_DocViewMode.visual] is de standaard: de
  /// gedeelde Markdown-editor (WYSIWYG via Quill, of rauw bij constructies die
  /// de brug niet aankan) als schrijfoppervlak. [_DocViewMode.source] toont de
  /// platte bron naast een live weergave.
  _DocViewMode _viewMode = _DocViewMode.visual;

  /// De focus van de rauwe editor. De opmaak-knoppenbalk geeft de focus hierheen
  /// terug na een klik, zodat je meteen verder typt.
  final FocusNode _editorFocus = FocusNode();

  /// Waar terwijl de controller van *buitenaf* wordt gelijkgetrokken aan de bron
  /// (ongedaan maken/opnieuw, of een invoeging): dan mag de controllerluisteraar
  /// niet terugstromen naar de notifier — dat zou een lus of dubbele bewerking
  /// geven.
  bool _applyingExternal = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(documentProvider).document?.source ?? '',
    );
    // Eén luisteraar vangt élke bronwijziging in de controller — typen én de
    // opmaak-knoppenbalk (die de controller rechtstreeks muteert en dus geen
    // onChanged afvuurt). Zo stroomt alles langs dezelfde weg naar de notifier.
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _editorFocus.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  /// Stroom een controllerwijziging naar de notifier. Slaat over wanneer de
  /// controller juist van búiten wordt bijgewerkt (`_applyingExternal`), en
  /// wanneer alleen de selectie/cursor verschoof (tekst gelijk) — anders zou een
  /// simpele cursorbeweging een lege bewerking worden.
  void _onControllerChanged() {
    _syncOutlineToMarkdownCaret();
    if (_applyingExternal) return;
    final text = _controller.text;
    final current = ref.read(documentProvider).document?.source ?? '';
    if (text == current) return;
    ref.read(documentProvider.notifier).edit(text, coalesceKey: 'doc');
  }

  void _setActiveOutlineIndex(int active) {
    if (active == _activeOutlineIndex) return;
    // Nooit setState vanuit een controller/Quill-listener tijdens build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || active == _activeOutlineIndex) return;
      setState(() => _activeOutlineIndex = active);
    });
  }

  /// Markeer in de Overzicht-rail de kop waaronder de markdown-caret staat.
  void _syncOutlineToMarkdownCaret() {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    _setActiveOutlineFromMarkdownOffset(sel.baseOffset);
  }

  /// Quill-caret → actieve Overzicht-kop via titelvolgorde in de platte tekst.
  void _syncOutlineToVisualCaret(String plain, int plainOffset) {
    final outline = buildMarkdownOutline(_controller.text);
    var active = -1;
    var searchFrom = 0;
    for (var i = 0; i < outline.length; i++) {
      final at = plain.indexOf(outline[i].title, searchFrom);
      if (at < 0) continue;
      if (at <= plainOffset) {
        active = i;
        searchFrom = at + outline[i].title.length;
      } else {
        break;
      }
    }
    _setActiveOutlineIndex(active);
  }

  void _setActiveOutlineFromMarkdownOffset(int offset) {
    final outline = buildMarkdownOutline(_controller.text);
    var active = -1;
    for (var i = 0; i < outline.length; i++) {
      if (outline[i].offset <= offset) {
        active = i;
      } else {
        break;
      }
    }
    _setActiveOutlineIndex(active);
  }

  /// Sla het document op. Cmd/Ctrl+S, net als een deck. Feedback is de dirty-stip
  /// op het tabblad die verdwijnt — geen aparte melding nodig.
  ///
  /// Heeft het al een pad, dan byte-getrouw terug naar dat pad (alleen als er
  /// iets veranderde). Een nog niet opgeslagen document (nieuw, geen pad) valt
  /// terug op 'Opslaan als…': kies een pad, schrijf, en zet het in de recente
  /// lijst — net als een deck.
  Future<void> _save() async {
    final state = ref.read(documentProvider);
    final document = state.document;
    if (document == null) return;
    final path = state.filePath;
    if (path != null) {
      if (!state.isDirty) return;
      if (await saveDocument(document, path) && mounted) {
        ref.read(documentProvider.notifier).markSaved(filePath: path);
      }
      return;
    }
    final saved = await ref.read(fileServiceProvider).saveDocumentAs(document);
    if (saved == null || !mounted) return;
    ref.read(documentProvider.notifier).markSaved(filePath: saved);
    await ref
        .read(settingsProvider.notifier)
        .addRecentFile(saved, kind: MarkdownKind.document);
  }

  /// De titel van dit document: de eerste H1, anders de bestandsnaam, anders
  /// leeg. Bepaalt de voorgestelde exportnaam en de HTML-`<title>` — net als een
  /// tekstverwerker een document naar zijn kop noemt.
  String _documentTitle(String source, String? filePath) {
    for (final line in source.split('\n')) {
      final m = RegExp(r'^#\s+(.+)$').firstMatch(line.trim());
      if (m != null) return m.group(1)!.trim();
    }
    if (filePath != null) return p.basenameWithoutExtension(filePath);
    return '';
  }

  /// Open de document-export-dialoog (DOCUMENT_MODE.md §11.2). De dialoog kiest
  /// profiel en formaat; het echte bouwen-en-wegschrijven gebeurt in de closure
  /// hieronder, die de bron langs `buildDocumentExportBundle → AudienceDeck`
  /// projecteert (nooit de rauwe bron), een pad laat kiezen en atomisch
  /// wegschrijft. De bron zelf blijft ongemoeid — export is een afgeleid bestand.
  Future<void> _export() async {
    final state = ref.read(documentProvider);
    final document = state.document;
    if (document == null) return;
    final settings = ref.read(settingsProvider);
    await DocumentExportDialog.show(
      context,
      privacyChecksEnabled: settings.privacyChecksEnabled,
      onExport: (profile, format) => _writeExport(profile, format),
    );
  }

  /// Bouwt de exportbundel voor het gekozen [profile], laat een pad kiezen met
  /// de juiste extensie, en schrijft de export weg. Geeft het geschreven pad
  /// terug, of `null` als de gebruiker de bestandskiezer wegklikte of het
  /// schrijven mislukte.
  Future<String?> _writeExport(
    PrivacyExportProfile profile,
    DocumentExportFormat format,
  ) async {
    final state = ref.read(documentProvider);
    final source = state.document?.source ?? '';
    final filePath = state.filePath;
    final projectPath = filePath == null ? null : p.dirname(filePath);
    final settings = ref.read(settingsProvider);
    final fileService = ref.read(fileServiceProvider);
    final imageService = ref.read(imageServiceProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final l10n = context.l10n;
    final title = _documentTitle(source, filePath);

    // Bouw de bundel langs de audited projectiegrens. Vanaf hier raakt geen
    // uitvoerpad de rauwe bron nog aan.
    final bundle = await buildDocumentExportBundle(
      source,
      projectPath: projectPath,
      profile: profile,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
      regions: settings.privacyRegions,
      disabledRules: settings.privacyDisabledRules,
      markdownService: markdownService,
      title: title,
    );

    if (format == DocumentExportFormat.ocideck) {
      return _writePackageExport(bundle);
    }

    // Kies een pad. De extensie én het profiel staan in de naam, zodat een
    // verwisseling (volledig ↔ geredigeerd) zichtbaar is.
    final ext = switch (format) {
      DocumentExportFormat.md => 'md',
      DocumentExportFormat.html => 'html',
      DocumentExportFormat.latex => 'tex',
      DocumentExportFormat.ocideck => 'ocideck',
    };
    final tag = profile == PrivacyExportProfile.redacted
        ? l10n.d('geredigeerd')
        : l10n.d('volledig');
    final base = _safeExportName(title.isEmpty ? l10n.d('document') : title);
    final dest = await pickDocumentExportDestination(
      dialogTitle: l10n.t('export'),
      fileName: '$base-$tag.$ext',
      initialDirectory: projectPath,
    );
    if (dest == null) return null;
    final outputPath = dest.endsWith('.$ext') ? dest : '$dest.$ext';

    // Afbeeldingen ingesloten als data:-URI, begrensd binnen de projectmap —
    // dezelfde regel als de deck-HTML-export: een pad buiten de map wordt
    // geweigerd, niet gevolgd.
    Future<String?> embed(String src) async {
      final bytes = await imageService.readSlideImageBytes(
        src,
        projectPath: projectPath,
      );
      if (bytes == null) return null;
      final encoded = encodeForHtmlEmbed(bytes, src);
      return encoded == null ? null : htmlImageDataUri(encoded);
    }

    return writeDocumentExport(
      bundle,
      format,
      html: MarpHtmlService(),
      theme: fileService.activeProfileFor(projectPath: projectPath),
      metadata: ExportDocumentMetadata(
        title: title,
        language: l10n.languageCode,
      ),
      embedImage: embed,
      outputPath: outputPath,
    );
  }

  /// Exporteer het geprojecteerde document als `.ocideck`-pakket (markdown +
  /// assets), met dezelfde versleutelingsdialoog als bij een presentatie.
  Future<String?> _writePackageExport(ExportBundle bundle) async {
    if (!mounted) return null;
    final choice = await PackageEncryptDialog.show(context);
    if (choice == null || !mounted) return null;
    final password = choice.encrypt ? choice.password : null;
    final fileService = ref.read(fileServiceProvider);
    final l10n = context.l10n;
    final deck = bundle.audience.deck;
    try {
      if (isWebPlatform) {
        return await fileService.downloadPackage(deck, password: password);
      }
      final picked = await fileService.pickPackageDestination(deck);
      if (picked == null) return null;
      await fileService.exportPackage(deck, picked, password: password);
      return picked;
    } catch (e) {
      logError('DocumentEditor: pakketexport mislukt', e);
      if (!mounted) return null;
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
      );
      return null;
    }
  }

  /// Converteer dit document naar een NIEUWE presentatie in een nieuw tabblad
  /// (DOCUMENT_MODE.md §11.3). Een expliciete kopie: dit document blijft
  /// ongemoeid. De dialoog toont het voorgestelde aantal dia's en de drop-lijst
  /// vóór het committen; pas bij bevestigen ontstaat het nieuwe tabblad.
  Future<void> _convertToPresentation() async {
    final state = ref.read(documentProvider);
    final source = state.document?.source ?? '';
    final title = _documentTitle(source, state.filePath);
    // De getypeerde, zero-loss deconstructie ís de bron van waarheid — voor het
    // voorgestelde aantal dia's én voor het nieuwe deck. Bewust niet
    // generateDeck→parseDeck: dat zou een kop-geleide sectie via `_inferSlideType`
    // weer stil kunnen laten vallen (§11.3, §11.5). De nieuwe presentatie is een
    // kopie; er reist geen zegel mee.
    final deck = DocumentDeckBridge.documentToDeck(source, title: title);
    final confirmed = await ConvertToPresentationDialog.show(
      context,
      slideCount: deck.slides.length,
    );
    if (confirmed != true || !mounted) return;
    ref.read(tabsProvider.notifier).newDeckInNewTab(title, slides: deck.slides);
  }

  /// Scroll / spring naar de aangeklikte kop uit de Overzicht-rail.
  ///
  /// Visueel: cursor in de notes-editor (markdown-offset of Quill-titel).
  /// Bron: cursor in de bron-editor + anker in de live weergave (docs-lezer-
  /// mechanisme).
  void _scrollToHeading(MarkdownOutlineEntry entry) {
    final source = ref.read(documentProvider).document?.source ?? '';
    final outline = buildMarkdownOutline(source);
    final outlineIndex = outline.indexWhere(
      (e) => e.offset == entry.offset && e.title == entry.title,
    );
    final offset = entry.offset.clamp(0, _controller.text.length);
    _controller.selection = TextSelection.collapsed(offset: offset);
    _editorFocus.requestFocus();
    setState(() {
      _activeOutlineIndex = outlineIndex;
      _revealMarkdownOffset = entry.offset;
      _revealTitle = entry.title;
      _revealSignal++;
    });

    if (_viewMode != _DocViewMode.source) return;
    final index = DocumentMarkdownView.headingBlockIndex(
      source,
      headingSlug(entry.title),
    );
    if (index < 0) return;
    setState(() => _anchorBlockIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wanneer de bron van búiten de editor verandert (ongedaan maken/opnieuw),
    // de controller bijwerken. Bij gewoon typen is de bron na de `edit` al gelijk
    // aan de controllertekst, dus dan doet dit niets — geen terugkoppellus.
    ref.listen(documentProvider.select((s) => s.document?.source ?? ''), (
      _,
      source,
    ) {
      if (source != _controller.text) {
        _applyingExternal = true;
        _controller.value = TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: source.length),
        );
        _applyingExternal = false;
      }
    });
    final source = ref.watch(
      documentProvider.select((s) => s.document?.source ?? ''),
    );
    final canUndo = ref.watch(documentProvider.select((s) => s.canUndo));
    final canRedo = ref.watch(documentProvider.select((s) => s.canRedo));
    final theme = Theme.of(context);
    return Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            _undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            _redo();
            return null;
          },
        ),
      },
      child: CallbackShortcuts(
        bindings: {
          // Cmd op macOS, Ctrl elders — net als het opslaan van een deck.
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): _redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): _redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        },
        child: Scaffold(
          body: Column(
            children: [
              _DocEditorToolbar(
                mode: _viewMode,
                onModeChanged: (m) => setState(() => _viewMode = m),
                onInsertChart: _insertChart,
                onInsertTable: _insertTable,
                onInsertMermaid: _insertMermaid,
                onInsertImage: _insertImage,
                onPaste: () => unawaited(_smartPaste()),
                onUndo: canUndo ? _undo : null,
                onRedo: canRedo ? _redo : null,
                onExport: _export,
                onOpenSettings: () => SettingsDialog.show(context),
                onConvertToPresentation: _convertToPresentation,
                controller: _controller,
                editorFocus: _editorFocus,
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _viewMode == _DocViewMode.visual
                      ? _visualLayout(theme, source, constraints)
                      : _sourceLayout(theme, source, constraints),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bron-modus: de rauwe bron en de live weergave naast elkaar op een breed
  /// venster, onder elkaar wanneer het te smal wordt voor twee leesbare kolommen.
  /// De Overzicht-rail komt erbij zodra er breedte genoeg is.
  Widget _sourceLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final editor = _editor(theme);
    final preview = _preview(theme, source);
    if (c.maxWidth < 760) {
      return Column(
        children: [
          Expanded(child: editor),
          Divider(height: 1, thickness: 1, color: divider),
          Expanded(child: preview),
        ],
      );
    }
    // Waar een presentatie de diastrook heeft, toont een document zijn koppen —
    // maar alleen als er breedte genoeg is voor rail + twee leesbare kolommen.
    final showRail = c.maxWidth >= 940;
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(child: editor),
        VerticalDivider(width: 1, thickness: 1, color: divider),
        Expanded(child: preview),
      ],
    );
  }

  /// Visuele modus: bewerkbaar schrijfoppervlak via de gedeelde
  /// [MarkdownNotesEditor] (WYSIWYG wanneer de bron dat toelaat, anders rauw
  /// markdown — beide bewerkbaar). Geen read-only preview meer als hoofdoppervlak.
  Widget _visualLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final showRail = c.maxWidth >= 940;
    final editor = MarkdownNotesEditor(
      controller: _controller,
      focusNode: _editorFocus,
      editorTheme: MarkdownEditorTheme.documentSurface(
        scheme: theme.colorScheme,
      ),
      hintText: '',
      expand: true,
      // Opmaakbalk zit al in [_DocEditorToolbar] voor de bron; hier toont de
      // notes-editor zijn eigen balk (Quill of markdown) passend bij de modus.
      showToolbar: true,
      showModeToggle: false,
      mode: NotesEditorMode.visual,
      surfaceStyle: NotesSurfaceStyle.document,
      bordered: false,
      revealSignal: _revealSignal,
      revealMarkdownOffset: _revealMarkdownOffset,
      revealTitle: _revealTitle,
      onVisualCaret: _syncOutlineToVisualCaret,
      tryConsumePaste: _smartPaste,
      // Afbeelding-knop → carrousel, geen `![beschrijving](pad-of-url)`-dump.
      onInsertImage: () => unawaited(_insertImage()),
    );
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(child: editor),
      ],
    );
  }

  Widget _editor(ThemeData theme) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyV, control: true):
          _DocSmartPasteIntent(),
      SingleActivator(LogicalKeyboardKey.keyV, meta: true):
          _DocSmartPasteIntent(),
    },
    child: Actions(
      actions: {
        _DocSmartPasteIntent: CallbackAction<_DocSmartPasteIntent>(
          onInvoke: (_) {
            unawaited(_smartPaste());
            return null;
          },
        ),
      },
      child: TextField(
        controller: _controller,
        focusNode: _editorFocus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: theme.colorScheme.primary,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          fontSize: 14,
          height: 1.5,
          color: theme.colorScheme.onSurface,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    ),
  );

  Widget _preview(ThemeData theme, String source, {bool centered = false}) =>
      Container(
        color: theme.colorScheme.surface,
        alignment: centered ? Alignment.topCenter : Alignment.topLeft,
        child: SingleChildScrollView(
          controller: _previewScroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: DocumentMarkdownView(
            source,
            maxTextWidth: 720,
            anchorBlockIndex: _anchorBlockIndex,
            anchorKey: _anchorKey,
            onEditChart: _editChart,
            onEditTable: _editTable,
          ),
        ),
      );

  /// De gedeelde dialoogschil voor het bewerken van een ingebedde kaart (grafiek
  /// of tabel): de volwaardige editor in een venster met Annuleren/Toepassen
  /// (bestaande l10n). Het venster mikt op 760×560 maar klemt op de
  /// kijkvenstermaat, zodat het ook op een klein of laag scherm past in plaats
  /// van horizontaal over te lopen (de vaste maat kromp zelf niet mee). Geeft
  /// `true` terug bij Toepassen.
  Future<bool?> _embedEditorDialog(Widget editor) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        final width = math.max(280.0, math.min(760.0, media.width - 96));
        final height = math.max(320.0, math.min(560.0, media.height - 160));
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          content: SizedBox(
            width: width,
            height: height,
            child: SingleChildScrollView(child: editor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.d('Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.d('Toepassen')),
            ),
          ],
        );
      },
    );
  }

  /// Dubbelklik op een gerenderde grafiek → de volwaardige [ChartEditor] in een
  /// dialoog (dezelfde editor als een dia, met een wegwerp-[Slide] om zijn bron
  /// vast te houden). 'Toepassen' schrijft het bewerkte ```chart-blok terug op
  /// zijn plek in de bron; de weergave hertekent mee. DOCUMENT_MODE.md §4.2.
  Future<void> _editChart(int chartOrdinal, String block) async {
    var edited = block;
    final slide = Slide.create(SlideType.chart).copyWith(customMarkdown: block);
    final apply = await _embedEditorDialog(
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => edited = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    final source = ref.read(documentProvider).document?.source ?? '';
    final next = replaceNthChartBlock(source, chartOrdinal, edited);
    if (next != source) {
      ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
    }
  }

  /// Dubbelklik op een gerenderde tabel → de volwaardige [TableEditor] in een
  /// dialoog. Kop + scheidingsrij + body worden via [decodeMarkdownTableWithAlignment]
  /// ontleed tot een celraster mét per-kolomuitlijning en in een wegwerp-[Slide]
  /// gezet; 'Toepassen' serialiseert raster én uitlijning terug naar een
  /// GFM-tabel en vervangt precies dat tabelblok in de bron. DOCUMENT_MODE.md §4.2.
  Future<void> _editTable(int tableOrdinal, List<String> rawRows) async {
    final source = ref.read(documentProvider).document?.source ?? '';
    // rawRows draagt de scheidingsrij niet; die haalt de uitlijning. Lees daarom
    // het volledige tabelblok (kop + scheiding + body) uit de bron.
    final range = DocumentMarkdownView.nthTableBlockRange(source, tableOrdinal);
    final tableLines = range == null
        ? rawRows
        : source.split('\n').sublist(range[0], range[1]);
    final decoded = decodeMarkdownTableWithAlignment(tableLines);
    var editedRows = decoded.rows;
    var editedAligns = decoded.alignments;
    final slide = Slide.create(SlideType.table).copyWith(
      tableRows: decoded.rows,
      tableColumnAlignments: decoded.alignments,
    );
    final apply = await _embedEditorDialog(
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        documentContext: true,
        onUpdate: (s) {
          editedRows = s.tableRows;
          editedAligns = s.tableColumnAlignments;
        },
      ),
    );
    if (apply != true || !mounted) return;
    final next = replaceNthTableBlock(
      source,
      tableOrdinal,
      encodeMarkdownTable(editedRows, alignments: editedAligns),
    );
    if (next != source) {
      ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
    }
  }

  /// Voeg [block] als een verse alinea in op de cursorpositie (of achteraan als
  /// er geen selectie is). De pure [insertBlockIntoSource] regelt de lege regels
  /// eromheen; hier zetten we de controller en de bron gelijk en plaatsen we de
  /// cursor ná het blok, zodat je meteen verder kunt typen. Een expliciete
  /// bewerking (`coalesceKey: null`) — geen samenvoeging met eerder typen.
  void _insertBlock(String block) {
    final sel = _controller.selection;
    final (next, cursor) = insertBlockIntoSource(
      _controller.text,
      sel.start,
      sel.end,
      block,
    );
    // Zet de controller (met cursor ná het blok) los van de luisteraar en dien de
    // bewerking als een eigen stap in (`coalesceKey: null`), zodat een invoeging
    // niet met eerder typen samenvloeit in de ongedaan-maken-geschiedenis.
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _applyingExternal = false;
    ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
  }

  /// Slim plakken: herkent afbeelding → `![](…)`, spreadsheet/tabel → GFM-
  /// tabel, anders opgeschoonde tekst. Geeft `true` als de plak is afgehandeld
  /// (dan mag de editor niet nóg eens plakken).
  Future<bool> _smartPaste() async {
    final state = ref.read(documentProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final imageService = ref.read(imageServiceProvider);
    final outcome = await imageService.pasteImageDetailed(
      projectPath: projectPath,
    );
    if (outcome.path != null) {
      _insertBlock('![](${outcome.path})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Afbeelding geplakt'))),
        );
      }
      return true;
    }
    // Geen afbeelding: stil als "geen klembordbeeld", anders de echte fout.
    if (outcome.failure != null &&
        outcome.failure != ImageImportFailure.noClipboardImage &&
        mounted) {
      reportImageImportFailure(context, outcome.failure);
      return true;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return false;

    final table = parseClipboardTable(raw);
    if (table != null && table.isNotEmpty) {
      _insertBlock(encodeMarkdownTable(table));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Tabel geplakt'))),
        );
      }
      return true;
    }

    final text = sanitizeMarkdownPaste(raw);
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : _controller.text.length;
    final end = sel.isValid ? sel.end : start;
    final next = _controller.text.replaceRange(start, end, text);
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _applyingExternal = false;
    ref.read(documentProvider.notifier).edit(next, coalesceKey: 'doc');
    return true;
  }

  void _undo() => ref.read(documentProvider.notifier).undo();
  void _redo() => ref.read(documentProvider.notifier).redo();

  /// Voeg een verse grafiek in: dezelfde [ChartEditor] als een dia (met een
  /// wegwerp-[Slide]), en bij 'Toepassen' een ```chart-blok op de cursorpositie.
  /// Identiek aan het dia-mechanisme — geen tweede grafiekweg (DOCUMENT_MODE.md
  /// §4.2). Zonder ingevulde data blijft het een geldig, later invulbaar blok.
  Future<void> _insertChart() async {
    final slide = Slide.create(SlideType.chart);
    var spec = ChartSpec.parse(slide.customMarkdown).toBlock();
    final apply = await _embedEditorDialog(
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => spec = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock('```chart\n$spec\n```');
  }

  /// Voeg een verse tabel in: de [TableEditor] met een leeg 2×2-raster, en bij
  /// 'Toepassen' een GFM-pijptabel op de cursorpositie.
  Future<void> _insertTable() async {
    final slide = Slide.create(SlideType.table);
    var rows = slide.tableRows;
    final apply = await _embedEditorDialog(
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        documentContext: true,
        onUpdate: (s) => rows = s.tableRows,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock(encodeMarkdownTable(rows));
  }

  /// Voeg een verse ```mermaid-fence in met een minimaal, taal-neutraal
  /// startdiagram (knoop-id's, geen tekst om te vertalen). Bewerken gaat via de
  /// bron — de dubbelklik is voor mermaid bewust overgeslagen (DOCUMENT_MODE.md).
  void _insertMermaid() =>
      _insertBlock('```mermaid\nflowchart TD\n  A --> B\n```');

  /// Voeg een afbeelding in via de carrousel (bibliotheken + open presentaties
  /// + Bladeren…). De gekozen file gaat door [ImageService.importIntoDeck]
  /// (grootte-cap, magic-bytes, kopie naar `images/` of staging) en landt als
  /// `![…](…)` op de cursorpositie — geen aparte assetweg naast de dia-import.
  Future<void> _insertImage() async {
    final state = ref.read(documentProvider);
    final settings = ref.read(settingsProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final tabs = ref.read(tabsProvider).tabs;
    // Zelfde afbeeldingspool als presentatiemodus: open decks + bibliotheek.
    // Recente presentaties leveren hun images/logos (niet de hele map).
    final searchPaths = documentImageSearchPaths(
      projectPath,
      settings.libraryPaths,
      openDeckProjectPaths: [
        for (final tab in tabs)
          ?tab.deckNotifierOrNull?.currentState.deck?.projectPath,
      ],
      recentPresentationDirectories: [
        for (final recent in settings.recentFiles)
          if (recent.kind.isPresentation) p.dirname(recent.path),
      ],
    );
    final picked = await ImageCarouselPicker.show(
      context,
      searchPaths: searchPaths,
      captionService: ref.read(captionServiceProvider),
      descriptionService: ref.read(descriptionServiceProvider),
      // Alleen deck-tabs: documenttabs hebben geen deckNotifier (gooit anders).
      openDeckFiles: [
        for (final tab in tabs) ?tab.deckNotifierOrNull?.currentState.filePath,
      ],
    );
    if (picked == null || !mounted) return;
    final reference = await ref
        .read(imageServiceProvider)
        .importIntoDeck(picked.path, projectPath: projectPath);
    if (!mounted) return;
    final alt = _markdownImageAlt(picked.caption);
    _insertBlock('![$alt]($reference)');
  }

  /// Alt-tekst voor `![…](…)`: carrousel-bijschrift, met `[`/`]` gestript zodat
  /// de markdown-syntaxis heel blijft.
  String _markdownImageAlt(String caption) {
    if (caption.isEmpty) return '';
    return caption.replaceAll('[', '').replaceAll(']', '');
  }

  /// De Overzicht-rail: de koppen van het document, live afgeleid, klikbaar om
  /// naar die kop te springen. Europa-header (EU-blauw + geel). Inklapbaar tot
  /// een smalle strook. Leeg document → lege rail.
  Widget _outlineRail(ThemeData theme, String source) {
    final outline = buildMarkdownOutline(source);
    final l10n = context.l10n;
    if (_outlineCollapsed) {
      return SizedBox(
        width: 40,
        child: Material(
          color: AppTheme.blueVivid,
          child: InkWell(
            onTap: () => setState(() => _outlineCollapsed = false),
            child: Tooltip(
              message: l10n.d('Overzicht uitklappen'),
              child: Center(
                child: Icon(
                  Icons.chevron_right,
                  color: AppTheme.amberVivid,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      key: const Key('document-outline-rail'),
      width: 216,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppTheme.blueVivid,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.d('Overzicht').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.amberVivid,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.d('Overzicht inklappen'),
                    onPressed: () => setState(() => _outlineCollapsed = true),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    color: AppTheme.amberVivid,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: theme.colorScheme.surface,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                itemCount: outline.length,
                itemBuilder: (context, i) => _outlineItem(
                  theme,
                  outline[i],
                  active: i == _activeOutlineIndex,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outlineItem(
    ThemeData theme,
    MarkdownOutlineEntry entry, {
    required bool active,
  }) => InkWell(
    onTap: () => _scrollToHeading(entry),
    child: Container(
      color: active
          ? AppTheme.blueVivid.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: EdgeInsets.only(
        left: 16 + (entry.level - 1).clamp(0, 5) * 12.0,
        right: 10,
        top: 5,
        bottom: 5,
      ),
      child: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: entry.level <= 1 ? 13 : 12.5,
          fontWeight: active || entry.level <= 1
              ? FontWeight.w600
              : FontWeight.w400,
          color: active
              ? AppTheme.blueVivid
              : entry.level <= 1
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// De weergavemodus van de documenteditor. Twee manieren om naar hetzelfde
/// document te kijken, nooit een derde renderpad (DOCUMENT_MODE.md §2.1): de bron
/// als tekst, of de weergave als hoofdoppervlak.
enum _DocViewMode { visual, source }

/// De werkbalk bovenaan de documenteditor: links de segmentkeuze Visueel | Bron,
/// rechts het invoeg-palet. Top-level widget zodat het bewerkscherm zelf slank
/// blijft; de labels lopen via [l10n] mee met de langste taal (geen vaste
/// breedte, DOCUMENT_MODE.md §8).
class _DocEditorToolbar extends StatelessWidget {
  final _DocViewMode mode;
  final ValueChanged<_DocViewMode> onModeChanged;
  final VoidCallback onInsertChart;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertMermaid;
  final VoidCallback onInsertImage;
  final VoidCallback onPaste;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onExport;
  final VoidCallback onOpenSettings;
  final VoidCallback onConvertToPresentation;
  final TextEditingController controller;
  final FocusNode editorFocus;

  const _DocEditorToolbar({
    required this.mode,
    required this.onModeChanged,
    required this.onInsertChart,
    required this.onInsertTable,
    required this.onInsertMermaid,
    required this.onInsertImage,
    required this.onPaste,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onOpenSettings,
    required this.onConvertToPresentation,
    required this.controller,
    required this.editorFocus,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<_DocViewMode>(
                        segments: [
                          ButtonSegment(
                            value: _DocViewMode.visual,
                            label: Text(l10n.d('Visueel')),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 15,
                            ),
                          ),
                          ButtonSegment(
                            value: _DocViewMode.source,
                            label: Text(l10n.d('Bron')),
                            icon: const Icon(Icons.code, size: 15),
                          ),
                        ],
                        selected: {mode},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (s) => onModeChanged(s.first),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: l10n.d('Ongedaan maken'),
                        onPressed: onUndo,
                        icon: const Icon(Icons.undo, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: l10n.d('Opnieuw'),
                        onPressed: onRedo,
                        icon: const Icon(Icons.redo, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      _insertMenu(l10n),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onExport,
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: Text(l10n.d('Exporteren…')),
                      ),
                      _moreMenu(l10n),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Opmaak-knoppenbalk alleen in bron-modus: in Visueel heeft
          // MarkdownNotesEditor zijn eigen balk (Quill of markdown). Twee
          // balkjes op één controller zouden uit de pas lopen.
          if (mode == _DocViewMode.source)
            MarkdownEditorToolbar(
              controller: controller,
              focusNode: editorFocus,
              theme: MarkdownEditorTheme.documentSurface(scheme: scheme),
              bordered: false,
              onInsertImage: onInsertImage,
            ),
        ],
      ),
    );
  }

  /// Het invoeg-palet: één menu dat een rijk blok op de cursorpositie invoegt.
  /// Hergebruikt de bestaande labels (Grafiek/Tabel/Afbeelding); Mermaid is de
  /// productnaam van de fence. Elke keuze schrijft een verse, draagbare
  /// Markdown-constructie in de bron (DOCUMENT_MODE.md §4).
  Widget _insertMenu(AppLocalizations l10n) {
    return PopupMenuButton<int>(
      tooltip: l10n.d('Invoegen'),
      position: PopupMenuPosition.under,
      onSelected: (value) => switch (value) {
        0 => onInsertChart(),
        1 => onInsertTable(),
        2 => onInsertMermaid(),
        3 => onInsertImage(),
        _ => onPaste(),
      },
      itemBuilder: (context) => [
        _insertItem(0, Icons.bar_chart, l10n.d('Grafiek')),
        _insertItem(1, Icons.table_chart_outlined, l10n.d('Tabel')),
        _insertItem(2, Icons.account_tree_outlined, l10n.d('Mermaid')),
        _insertItem(3, Icons.image_outlined, l10n.d('Afbeelding')),
        _insertItem(4, Icons.content_paste, l10n.d('Plakken')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16),
            const SizedBox(width: 4),
            Text(l10n.d('Invoegen'), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Het overloopmenu rechts: Instellingen (anders alleen via macOS-menubalk
  /// bereikbaar in documentmodus) en conversie naar presentatie.
  Widget _moreMenu(AppLocalizations l10n) {
    return PopupMenuButton<int>(
      tooltip: l10n.t('more'),
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        switch (value) {
          case 0:
            onOpenSettings();
          case 1:
            onConvertToPresentation();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 17),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.t('settings'))),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              const Icon(Icons.slideshow_outlined, size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Converteer naar presentatie…'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<int> _insertItem(int value, IconData icon, String label) {
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

/// Voeg [block] in [source] in op het bereik [selStart]–[selEnd] (een negatieve
/// start betekent 'geen cursor' → achteraan), omgeven door precies genoeg lege
/// regels om een eigen alinea te vormen zonder er ooit meer dan één dubbele
/// witregel van te maken. Geeft de nieuwe bron én de cursorpositie ná het
/// ingevoegde blok terug. Top-level en puur, zodat de invoeglogica los toetsbaar
/// is van het editor-scherm — net als de terugschrijf-helpers hierboven.
(String, int) insertBlockIntoSource(
  String source,
  int selStart,
  int selEnd,
  String block,
) {
  final start = selStart < 0 ? source.length : math.min(selStart, selEnd);
  final end = selEnd < 0 ? source.length : math.max(selStart, selEnd);
  final before = source.substring(0, start);
  final after = source.substring(end);
  final lead = before.isEmpty
      ? ''
      : before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trail = after.isEmpty
      ? '\n'
      : after.startsWith('\n')
      ? ''
      : '\n\n';
  final insertion = '$lead$block$trail';
  return ('$before$insertion$after', before.length + insertion.length);
}

/// Een bestandsnaam-veilige vorm van [title] voor de voorgestelde exportnaam:
/// alles wat geen letter/cijfer/koppelteken is wordt een koppelteken, samengedrukt
/// en getrimd. Top-level en puur, los toetsbaar van het editor-scherm.
String _safeExportName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^\w\- ]+'), '')
      .trim()
      .replaceAll(RegExp(r'[\s]+'), '-');
  return cleaned.isEmpty ? 'document' : cleaned;
}

class _DocSmartPasteIntent extends Intent {
  const _DocSmartPasteIntent();
}

/// Vervang de inhoud van het `chartOrdinal`-de ```chart-blok (vanaf 0) in
/// [source] door [newContent] (de kale spec-tekst, zonder fence). Andere blokken
/// — en alle tekst eromheen — blijven byte-getrouw staan; een `chartOrdinal`
/// buiten bereik laat de bron ongemoeid. Top-level en puur, zodat de
/// terugschrijf-logica los toetsbaar is van het editor-scherm.
String replaceNthChartBlock(
  String source,
  int chartOrdinal,
  String newContent,
) {
  var seen = 0;
  return source.replaceAllMapped(chartFencePattern, (m) {
    if (seen++ != chartOrdinal) return m.group(0)!;
    return '```chart\n$newContent\n```';
  });
}

/// Vervang het `tableOrdinal`-de GFM-tabelblok (vanaf 0) in [source] door
/// [newGfm], en laat elke andere byte staan. De regel-reikwijdte komt van
/// [DocumentMarkdownView.nthTableBlockRange], zodat de telling exact die van de
/// weergave volgt; een ordinaal buiten bereik laat de bron ongemoeid. Top-level
/// en puur, zodat de terugschrijf-logica los toetsbaar is.
String replaceNthTableBlock(String source, int tableOrdinal, String newGfm) {
  final range = DocumentMarkdownView.nthTableBlockRange(source, tableOrdinal);
  if (range == null) return source;
  final lines = source.split('\n');
  lines.replaceRange(range[0], range[1], newGfm.split('\n'));
  return lines.join('\n');
}
