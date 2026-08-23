import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../services/file_service.dart';
import '../../services/import/bulk_import_runner.dart';
import '../../services/import/deck_builder.dart';
import '../../services/import/pipeline/import_task.dart';
import '../../services/import/presentation_import_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/user_facing_error.dart';

/// De wachtrij voor een import van meer dan één presentatie (#772).
///
/// Waarom een wachtrij en geen tien tabbladen: bij een handvol bestanden is
/// "alles open" geen resultaat maar een puinhoop. De gebruiker zet de volgorde
/// goed, wijst één doelmap aan, en krijgt achteraf te lezen wat er landde en
/// waar. Elk deck wordt als eigen `.md` weggeschreven — met, zoals overal in
/// OciDeck, zijn `images/` naast het bestand.
///
/// Eén bestand komt hier nooit: dat opent gewoon in een tab (zie
/// `importPresentation`). De grens ligt bij "meer dan één", omdat pas dan de
/// vragen ontstaan die deze dialoog stelt.
class PresentationImportQueueDialog extends StatefulWidget {
  const PresentationImportQueueDialog({
    super.key,
    required this.files,
    required this.fileService,
    this.initialDirectory,
  });

  final List<BulkImportItem> files;

  /// De schrijver van de omgezette decks. Meegegeven in plaats van hier
  /// gemaakt: de aanroeper heeft de Riverpod-container en dus de ingestelde
  /// thuismap, taal en stijlprofiel.
  final FileService fileService;

  /// De map waarin de mapkiezer opent — en, wanneer meegegeven, meteen de
  /// gekozen doelmap. Dat tweede is de testnaad: de statische `FilePicker`
  /// laat zich onder `flutter test` niet aansturen, net als bij
  /// `directoryOverride` van de OpenKAT-actie.
  final String? initialDirectory;

  /// Geeft de uitkomst terug, of null wanneer de gebruiker afzag van de import.
  static Future<BulkImportSummary?> show(
    BuildContext context, {
    required List<BulkImportItem> files,
    required FileService fileService,
    String? initialDirectory,
  }) {
    return showDialog<BulkImportSummary>(
      context: context,
      // Halverwege wegklikken zou een rij achterlaten die doorloopt zonder
      // scherm; sluiten kan met de knoppen.
      barrierDismissible: false,
      builder: (_) => PresentationImportQueueDialog(
        files: files,
        fileService: fileService,
        initialDirectory: initialDirectory,
      ),
    );
  }

  @override
  State<PresentationImportQueueDialog> createState() =>
      _PresentationImportQueueDialogState();
}

class _PresentationImportQueueDialogState
    extends State<PresentationImportQueueDialog> {
  late final List<BulkImportItem> _queue = [...widget.files];
  String? _directory;

  bool _running = false;
  bool _stopRequested = false;

  /// De annuleertoken van de lopende rij. Stoppen zet niet alleen
  /// [_stopRequested] (tussen twee bestanden) maar cancelt ook deze token, zodat
  /// de worker het lezen midden in het huidige bestand afbreekt (#875).
  ImportCancelToken? _cancel;
  BulkImportProgress? _progress;

  /// De uitkomsten zoals ze binnenkomen, zodat elke regel tijdens het draaien
  /// al zijn eigen vinkje of kruisje krijgt in plaats van pas achteraf.
  final List<BulkImportOutcome> _finished = [];
  BulkImportSummary? _summary;

  @override
  void initState() {
    super.initState();
    _directory = widget.initialDirectory;
  }

  bool get _canStart =>
      !_running && _summary == null && _queue.isNotEmpty && _directory != null;

  Future<void> _pickDirectory() async {
    // Zelfde poort als elke andere getDirectoryPath-aanroep: op web bestaat de
    // mapkiezer niet en geeft hij stil null terug (#150).
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map kiezen'),
      initialDirectory: _directory ?? widget.initialDirectory,
    );
    if (!mounted || result == null) return;
    setState(() => _directory = result);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _queue.length) return;
    setState(() => _queue.insert(target, _queue.removeAt(index)));
  }

  void _remove(int index) => setState(() => _queue.removeAt(index));

  Future<void> _start() async {
    final directory = _directory;
    if (directory == null) return;
    // Vóór de eerste await vastgelegd; de translator wordt tijdens de async run
    // aangeroepen en mag niet van een dan mogelijk verdwenen context afhangen.
    final translate = context.l10n.d;
    final cancel = ImportCancelToken();
    setState(() {
      _running = true;
      _stopRequested = false;
      _cancel = cancel;
      _finished.clear();
    });
    // `translate: l10n.d` zet de notitiedia's in het document in de taal van de
    // gebruiker (#806); de service geeft de naad door aan zijn `DeckBuilder`.
    final runner = BulkImportRunner(
      writeDeck: widget.fileService.saveDeck,
      pathExists: (path) => File(path).existsSync(),
      service: PresentationImportService(
        builder: DeckBuilder(translate: translate),
      ),
    );
    final summary = await runner.run(
      _queue,
      targetDirectory: directory,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
      onFileDone: (outcome) {
        if (mounted) setState(() => _finished.add(outcome));
      },
      shouldStop: () => _stopRequested,
      cancel: cancel,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = null;
      _cancel = null;
      _summary = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      // Tijdens het omzetten niet weg te klikken: de rij loopt door en het
      // scherm is het enige dat vertelt hoe ver hij is.
      canPop: !_running,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.slideshow_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Presentaties importeren'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_queue.length}',
              style: TextStyle(fontSize: 13, color: AppTheme.slate500),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.d(
                  'Elk bestand wordt apart omgezet en als eigen presentatie in de doelmap opgeslagen. Gaat er één mis, dan loopt de rij gewoon door.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 10),
              _destination(l10n),
              const SizedBox(height: 10),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _queue.length; i++) _row(l10n, i),
                      ],
                    ),
                  ),
                ),
              ),
              if (_running) ...[const SizedBox(height: 10), _progressBar(l10n)],
              if (_summary != null) ...[
                const SizedBox(height: 10),
                _summaryBox(l10n, _summary!),
              ],
            ],
          ),
        ),
        actions: _actions(l10n),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    if (_summary != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context, _summary),
          child: Text(l10n.d('Sluiten')),
        ),
      ];
    }
    if (_running) {
      return [
        TextButton(
          onPressed: _stopRequested
              ? null
              : () {
                  _cancel?.cancel();
                  setState(() => _stopRequested = true);
                },
          child: Text(l10n.d('Stoppen')),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(l10n.d('Annuleren')),
      ),
      FilledButton.icon(
        onPressed: _canStart ? _start : null,
        icon: const Icon(Icons.play_arrow, size: 16),
        label: Text(l10n.d('Importeren')),
      ),
    ];
  }

  /// De doelmap plus de reden waarom een aparte map hier verstandig is. Die
  /// tip staat woordelijk ook in de waarschuwing vooraf, en met opzet: daar is
  /// het een algemene raad, hier gaat het om een map die de gebruiker op dit
  /// moment aanwijst.
  Widget _destination(AppLocalizations l10n) {
    final directory = _directory;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: AppTheme.slate400),
              const SizedBox(width: 8),
              Text(
                l10n.d('Doelmap'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            directory ?? l10n.d('Nog geen doelmap gekozen'),
            style: TextStyle(
              fontSize: 12,
              color: directory == null ? AppTheme.slate400 : AppTheme.slate700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (supportsLocalProjectFolders)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _running || _summary != null ? null : _pickDirectory,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(
                  directory == null
                      ? l10n.d('Map kiezen')
                      : l10n.d('Andere map…'),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.d(
                  'Meerdere presentaties tegelijk importeren schrijft ze als bestanden naar een map; in de browserversie kan dat niet.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.dangerFg),
              ),
            ),
          Text(
            l10n.d(
              'Tip: bewaar geïmporteerde presentaties in een aparte map. De kwaliteit verschilt per bron, en zo blijft geïmporteerd materiaal gescheiden van uw eigen werk.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }

  /// Eén regel in de rij: volgnummer of status, de bestandsnaam, en — zolang de
  /// rij nog niet loopt — de knoppen om te herordenen en te verwijderen.
  Widget _row(AppLocalizations l10n, int index) {
    final item = _queue[index];
    final editable = !_running && _summary == null;
    final outcome = index < _finished.length ? _finished[index] : null;
    final busy = _running && _progress?.index == index && outcome == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 26, child: _rowLeading(index, outcome, busy)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (outcome != null)
                  Text(
                    _outcomeLine(l10n, outcome),
                    style: TextStyle(
                      fontSize: 11,
                      color: outcome.isSuccess
                          ? AppTheme.slate400
                          : AppTheme.dangerFg,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              tooltip: l10n.d('Omhoog'),
              onPressed: index == 0 ? null : () => _move(index, -1),
              icon: const Icon(Icons.arrow_upward, size: 16),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: l10n.d('Omlaag'),
              onPressed: index == _queue.length - 1
                  ? null
                  : () => _move(index, 1),
              icon: const Icon(Icons.arrow_downward, size: 16),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: l10n.d('Uit de rij halen'),
              onPressed: () => _remove(index),
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowLeading(int index, BulkImportOutcome? outcome, bool busy) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (outcome != null) {
      return Icon(
        outcome.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
        size: 16,
        color: outcome.isSuccess ? AppTheme.successFg : AppTheme.dangerFg,
      );
    }
    return Text(
      '${index + 1}.',
      style: TextStyle(fontSize: 12, color: AppTheme.slate400),
    );
  }

  String _outcomeLine(AppLocalizations l10n, BulkImportOutcome outcome) {
    if (!outcome.isSuccess) {
      return outcome.failure == null
          ? l10n.d('mislukt')
          : importFailureText(l10n, outcome.failure!);
    }
    final slides = '${outcome.slideCount} ${l10n.d('dia’s')}';
    if (outcome.problemSlides == 0) return slides;
    return '$slides · ${outcome.problemSlides} '
        '${l10n.d('dia’s vragen aandacht')}';
  }

  Widget _progressBar(AppLocalizations l10n) {
    final progress = _progress;
    final done = _finished.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.d('Bezig met importeren…'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
            Text(
              '$done / ${_queue.length}',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: progress?.fileProgress),
        if (progress != null && progress.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // `progress.message` is een vaste Nederlandse voortgangsstring uit
              // de servicelaag (die geen `BuildContext` heeft); `l10n.d` vertaalt
              // hem hier. Bewaakt door `app_localizations_test`, die deze
              // bronsleutels via `sourceKeysIn('lib')` meepakt (#806).
              '${progress.name} · ${l10n.d(progress.message)}',
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// Wat er is gebeurd, in getallen plus de plek waar het staat. De map is het
  /// belangrijkste van dit blok: de decks openen niet, dus zonder pad weet
  /// niemand waar zijn werk heen ging.
  Widget _summaryBox(AppLocalizations l10n, BulkImportSummary summary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Resultaat'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _summaryLine(l10n, summary),
            style: TextStyle(fontSize: 12, color: AppTheme.slate700),
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.d('Opgeslagen in')}: ${summary.targetDirectory}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }

  String _summaryLine(AppLocalizations l10n, BulkImportSummary summary) {
    final parts = <String>[
      '${summary.succeeded} ${l10n.d('geslaagd')}',
      '${summary.failed} ${l10n.d('mislukt')}',
      if (summary.problemSlides > 0)
        '${summary.problemSlides} ${l10n.d('dia’s vragen aandacht')}',
      if (summary.notReached > 0)
        '${summary.notReached} ${l10n.d('niet meer aan de beurt gekomen')}',
    ];
    return parts.join(' · ');
  }
}
