import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/markdown_kind.dart';
import '../../services/file_service.dart';
import '../../theme/app_theme.dart';
import '../reader/document_markdown_view.dart';
import '../slides/slide_preview.dart';
import 'open_kind_chrome.dart';

/// Het gerenderde voorbeeld naast een openlijst: zie wat er in een bestand
/// staat vóórdat je het opent.
///
/// Optioneel (instelling `showOpenPreview`, standaard uit). Het voorbeeld leest
/// een bestand dat de gebruiker nog niet gekozen heeft, en dat mag niet
/// ongevraagd gebeuren — wie het aanzet, kiest daar bewust voor.
///
/// Het lezen loopt door exact dezelfde fail-closed poort als het openen zelf
/// ([FileService.openDeckDetailed] / [FileService.openDocumentDetailed]): de
/// veiligheidsscan draait op de bytes die hier getekend worden. Een bestand dat
/// je niet mág openen, wordt hier dus ook niet getekend — dan staat er waarom
/// niet. Anders zou het voorbeeld een achterdeur zijn om onvertrouwde inhoud
/// alsnog te laten renderen.
class OpenPreviewPane extends StatefulWidget {
  const OpenPreviewPane({
    super.key,
    required this.fileService,
    required this.path,
  });

  final FileService fileService;

  /// Het aangewezen bestand, of null wanneer er nog niets is aangewezen.
  final String? path;

  /// Hoeveel tekens van een document getekend worden. Een voorbeeld is een
  /// eerste indruk, geen lezer: een boek van een megabyte hoort de lijst niet
  /// te laten haperen terwijl je er met de muis langsgaat.
  static const previewChars = 6000;

  /// Wachttijd voordat een aangewezen bestand daadwerkelijk gelezen wordt. Wie
  /// met de muis langs twintig rijen glijdt, wijst er twintig aan; zonder deze
  /// pauze zou dat twintig bestanden lezen en parseren voor één dat hij wilde
  /// zien.
  static const settleDelay = Duration(milliseconds: 250);

  @override
  State<OpenPreviewPane> createState() => _OpenPreviewPaneState();
}

class _OpenPreviewPaneState extends State<OpenPreviewPane> {
  /// Het pad waarvan de uitkomst hieronder staat; voorkomt herladen bij elke
  /// herbouw van het scherm.
  String? _loadedPath;
  bool _loading = false;

  Deck? _deck;
  String? _documentSource;
  bool _refused = false;

  /// Loopt tijdens [OpenPreviewPane.settleDelay]; een nieuwe aanwijzing zet hem
  /// terug op nul.
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(OpenPreviewPane old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _scheduleLoad();
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _scheduleLoad() {
    _settle?.cancel();
    if (widget.path == null || widget.path == _loadedPath) return;
    _settle = Timer(OpenPreviewPane.settleDelay, _load);
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null || path == _loadedPath) return;
    setState(() {
      _loading = true;
      _loadedPath = path;
      _deck = null;
      _documentSource = null;
      _refused = false;
    });
    final outcome = await widget.fileService.openDeckDetailed(path);
    Deck? deck = outcome.deck;
    String? source;
    var refused = false;
    if (deck == null) {
      // Dezelfde router als het openen: geen deck én "geen presentatie" betekent
      // plat document; elke andere reden is een weigering.
      if (outcome.failure == OpenFailure.notPresentation) {
        final doc = await widget.fileService.openDocumentDetailed(path);
        source = doc.document?.source;
        refused = source == null;
      } else {
        refused = true;
      }
    }
    if (!mounted) return;
    // Ondertussen een ander bestand aangewezen: die uitkomst wint.
    if (_loadedPath != path) return;
    setState(() {
      _loading = false;
      _deck = deck;
      _documentSource = source;
      _refused = refused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(l10n),
            const SizedBox(height: 8),
            Expanded(child: _body(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final path = widget.path;
    if (path == null) {
      return Text(
        l10n.d('Voorbeeld'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.slate600,
        ),
      );
    }
    final kind = _deck == null
        ? MarkdownKind.document
        : MarkdownKind.presentation;
    return Row(
      children: [
        Icon(markdownKindIcon(kind), size: 14, color: AppTheme.slate500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            p.basename(path),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (widget.path == null) {
      return _note(
        l10n.d('Wijs een bestand aan om er hier een voorbeeld van te zien.'),
      );
    }
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_refused) {
      return _note(
        l10n.d(
          'Dit bestand kan niet worden getoond. Openen weigert het ook — de inhoud is onveilig, beschadigd of onleesbaar.',
        ),
      );
    }
    final deck = _deck;
    if (deck != null) return _deckPreview(l10n, deck);
    return _documentPreview(l10n, _documentSource ?? '');
  }

  /// De eerste dia, op ware verhouding — dat is wat iemand als "de voorkant"
  /// van een presentatie herkent.
  Widget _deckPreview(AppLocalizations l10n, Deck deck) {
    if (deck.slides.isEmpty) {
      return _note(l10n.d('Deze presentatie heeft nog geen dia.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RepaintBoundary(
              child: SlidePreviewWidget(
                slide: deck.slides.first,
                projectPath: deck.projectPath,
                themeProfile: deck.themeProfile,
                deckMarpStyle: deck.marpStyle,
                // Een voorbeeld is klein; op ware grootte decoderen kost per
                // telefoonfoto tientallen MiB (#612). Zelfde grens als de
                // slidestrook.
                decodeMaxEdge: 512,
                slideNumber: 1,
                slideCount: deck.slides.length,
                tlp: deck.tlp,
                organization: deck.organization,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${deck.slides.length} ${l10n.t('slides')}',
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ],
    );
  }

  Widget _documentPreview(AppLocalizations l10n, String source) {
    if (source.trim().isEmpty) return _note(l10n.d('Dit document is leeg.'));
    final truncated = source.length > OpenPreviewPane.previewChars;
    final shown = truncated
        ? source.substring(0, OpenPreviewPane.previewChars)
        : source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: DocumentMarkdownView(shown, maxTextWidth: null),
          ),
        ),
        if (truncated) ...[
          const SizedBox(height: 6),
          Text(
            l10n.d('Alleen het begin van het document wordt getoond.'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ],
    );
  }

  Widget _note(String message) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppTheme.slate500),
    ),
  );
}
