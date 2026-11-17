// De transcriptie-dialoog voor een bestaand bestand (#2515, contract
// §3.2): voorbeschouwing → expliciete start → decode + definitieve pass →
// het resultaat opent als gewoon document.
//
// Drie dingen die dit venster eerlijk maakt vóór er iets start:
//  * het bestand wordt benoemd (naam, grootte, container, duur als die
//    zonder decode te zien is) — geen verrassing achteraf;
//  * de route staat erbij: lokaal met het gekozen model, of de
//    serverroute mét host en bestandsnaam — de Start-knop ís dan de
//    toestemming per taak (§4.3), er is geen aparte "versturen"-stap;
//  * de bewaarkeuze voor de audio staat erbij (desktop): een kopie naar
//    `media/` naast het document bij Opslaan, of helemaal geen kopie.
//
// Wat hij niet doet: tekst in een open deck of document injecteren. De
// enige uitkomst is een nieuw transcriptdocument — bewerken en opslaan
// zijn daarna de gewone documentwegen.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/call_audio_manifest.dart';
import '../../meetings/call_recording.dart';
import '../../services/transcription/capture_source.dart';
import '../../services/transcription/clip_recorded_audio.dart';
import '../../services/media/youtube_transcript.dart';
import '../../services/transcription/recording_staging.dart';
import '../../services/web_asset_store.dart';
import '../../services/transcription/file_capture_source.dart';
import '../../services/transcription/local_whisper_engine.dart';
import '../../services/transcription/media_sniff.dart';
import '../../services/transcription/transcript_document.dart';
import '../../services/transcription/transcription_engine.dart';
import '../../services/transcription/transcription_errors.dart';
import '../../state/tabs_provider.dart';
import '../../state/transcription_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/file_extension.dart';
import 'settings_dialog.dart';

/// Houd de bron al vast tussen het openen van de route en initState.
Future<void> showTranscribeFileDialog(
  BuildContext context, {
  required String sourcePath,
  required String displayName,
  YoutubeTranscriptOrigin? youtubeOrigin,
}) async {
  final lease = WebAssetStore.lease([
    sourcePath,
    ?WebAssetStore.pathForName('$sourcePath.sources.json'),
  ]);
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => TranscribeFileDialog(
        sourcePath: sourcePath,
        displayName: displayName,
        youtubeOrigin: youtubeOrigin,
      ),
    );
  } finally {
    lease.release();
  }
}

/// De fasen van de flow — één toestand, nooit twee schermen tegelijk.
enum _Phase {
  /// De voorbeschouwing is geladen; de knop staat klaar.
  ready,

  /// Decode of transcriptie loopt; de voortgang volgt.
  running,

  /// Getypte fout of "geen spraak" — leesbaar, met sluiten als uitweg.
  failed,
}

/// De transcriptie-flow voor één gekozen bestand. [sourcePath] is het
/// pad (desktop) of de `mem:`-sleutel (web) die de actie voorbereidde;
/// [displayName] is de naam zoals de gebruiker hem koos.
class TranscribeFileDialog extends ConsumerStatefulWidget {
  const TranscribeFileDialog({
    super.key,
    required this.sourcePath,
    required this.displayName,
    this.youtubeOrigin,
  });

  final String sourcePath;
  final String displayName;
  final YoutubeTranscriptOrigin? youtubeOrigin;

  @override
  ConsumerState<TranscribeFileDialog> createState() =>
      _TranscribeFileDialogState();
}

class _TranscribeFileDialogState extends ConsumerState<TranscribeFileDialog> {
  _Phase _phase = _Phase.ready;

  FileSourceInfo? _info;
  Object? _error;

  /// Loopt de decode of de transcriptie — de voortgangsstrook vertaalt.
  var _decoding = false;
  double? _progress;

  String _language = 'auto';
  var _keepAudio = false;

  FileCaptureSource? _source;
  FileCaptureSession? _session;
  TranscriptionEngine? _engine;
  String? _stagingDir;
  RecordingStaging? _stagingOwner;
  WebAssetLease? _sourceLease;
  bool _taskRunning = false;
  bool _cancelRequested = false;
  bool _disposed = false;

  /// Herkomst van een callopname (#2530): ligt de duurzame wav in een
  /// sessiemap met `sources.json`, dan is dit geen "bestand" maar een
  /// vergadering — en het manifest zegt welke bronstukken ontbraken.
  Map<String, Object?>? _callManifest;

  /// De talen waar de actieve engine voor staat, uit zijn
  /// `capabilities()` — `auto` voorop, de rest alfabetisch (#2940).
  /// `['auto']` als er nog geen melding binnen is: nooit een taal aanbieden
  /// die de engine niet meldde.
  List<String> _languages = const ['auto'];

  /// Diarisatie wordt alleen aangeboden als de engine het meldt —
  /// [EngineCapabilities.diarization]. Geen melding, geen checkbox;
  /// een niet-bestaande belofte is erger dan een ontbrekende (#2935).
  bool _diarize = false;
  bool _diarizationAvailable = false;

  @override
  void initState() {
    super.initState();
    _sourceLease = WebAssetStore.lease([
      widget.sourcePath,
      ?WebAssetStore.pathForName('${widget.sourcePath}.sources.json'),
    ]);
    _describe();
  }

  Future<void> _describe() async {
    final source = _fileSource();
    // De taalkeuze is capability-gedreven: de engine meldt zijn tabel en de
    // dialoog toont precies die — geen vaste vijf-talen-lijst meer (#2940).
    unawaited(_loadLanguages());
    try {
      // Synchroon: het manifest is hooguit enkele honderden bytes en een
      // async lees keert in een widgettest-zone nooit terug. Op web is dit
      // de `mem:`-sidecar die de sessie naast de wav-sleutel zette.
      _callManifest = readCallSources(widget.sourcePath);
      final info = await source.describe(widget.sourcePath);
      if (mounted) setState(() => _info = info);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.failed;
        });
      }
    }
  }

  Future<void> _loadLanguages() async {
    final engine = ref.read(transcriptionEngineProvider);
    if (engine == null) return;
    final caps = await engine.capabilities();
    if (!mounted ||
        _phase != _Phase.ready ||
        !identical(ref.read(transcriptionEngineProvider), engine)) {
      return;
    }
    final sorted = caps.languages.toList()..sort();
    sorted.remove('auto');
    if (caps.automaticLanguage) sorted.insert(0, 'auto');
    if (caps.languageSwitching) {
      sorted.insert(caps.automaticLanguage ? 1 : sorted.length, 'mixed');
    }
    setState(() {
      if (sorted.isNotEmpty) {
        _languages = sorted;
        if (!_languages.contains(_language)) _language = _languages.first;
      }
      _diarizationAvailable = caps.diarization;
    });
  }

  /// De bestandsbron uit het register — dezelfde instantie die de
  /// instellingskaart voor zijn capability-rij gebruikt.
  FileCaptureSource _fileSource() {
    return _source ??=
        ref.read(captureSourcesProvider)[CaptureSourceKind.file]
            as FileCaptureSource;
  }

  Future<void> _start() async {
    final engine = ref.read(transcriptionEngineProvider);
    if (engine == null) {
      setState(() {
        _error = const EngineUnavailable('geen engine geconfigureerd');
        _phase = _Phase.failed;
      });
      return;
    }
    _engine = engine;
    _cancelRequested = false;
    _taskRunning = true;
    RecordedAudio? audio;
    setState(() {
      _phase = _Phase.running;
      _decoding = !_info!.engineReadsDirectly;
      _progress = null;
    });
    try {
      _stagingOwner = ref.read(recordingStagingProvider);
      final stagingDir = kIsWeb
          ? null
          : await _stagingOwner!.createSessionDir();
      _stagingDir = stagingDir;
      _checkTaskActive();
      final session = await _fileSource().start(
        CaptureRequest(
          kinds: const {CaptureSourceKind.file},
          // De deelnemersmelding staat in het venster zelf — de keuze om
          // dit bestand te verwerken is bewust gemaakt.
          consent: const RecordingConsent(participantNoticeAcknowledged: true),
          stagingDir: stagingDir,
          sourcePath: widget.sourcePath,
        ),
      );
      _session = session;
      if (_cancelRequested || !mounted) {
        session.cancel();
        _checkTaskActive();
      }
      audio = await session.stop();
      _checkTaskActive();
      final origin = widget.youtubeOrigin;
      if (origin != null &&
          (origin.start > Duration.zero || origin.end != null)) {
        audio = await clipRecordedAudio(
          audio,
          start: origin.start,
          end: origin.end,
          stagingDir: stagingDir,
          cancelled: () => _cancelRequested || !mounted,
        );
        _checkTaskActive();
      }
      if (mounted) setState(() => _decoding = false);

      // De toestemming noemt host én bestand — de dialoog toonde beide en
      // de Start-knop was de bevestiging (§4.3).
      final profile = ref.read(asrServerProfileProvider);
      final options = TranscriptionOptions(
        language: _language == 'auto' || _language == 'mixed'
            ? null
            : _language,
        languageSwitching: _language == 'mixed',
        diarize: _diarize,
        serverConsent: engine.kind == EngineKind.batchServer
            ? ServerConsent(host: profile.host, audioPath: audio.durablePath)
            : null,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      final result = await engine.transcribe(
        AudioRef(audio.durablePath),
        options,
      );

      _checkTaskActive();
      final body = formatTranscriptBody(result.segments);
      if (body.trim().isEmpty) {
        await _discardStaging();
        if (mounted) {
          setState(() {
            _error = _NoSpeechFound(widget.displayName);
            _phase = _Phase.failed;
          });
        }
        return;
      }
      await _openDocument(result, audio.duration, engine);
    } on Cancelled {
      await _discardStaging();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      await _discardStaging();
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.failed;
        });
      }
    } finally {
      audio?.releaseAssets();
      _taskRunning = false;
      if (_disposed) _sourceLease?.release();
    }
  }

  void _checkTaskActive() {
    if (_cancelRequested || !mounted) {
      throw const Cancelled('transcriptietaak gesloten');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    if (!_taskRunning) _sourceLease?.release();
    super.dispose();
  }

  /// De gedecodeerde WAV in staging is een tussenstap — de audio die de
  /// gebruiker bewaart is het origineel, dus de staging gaat altijd weg.
  Future<void> _discardStaging() async {
    final dir = _stagingDir;
    _stagingDir = null;
    if (dir == null) return;
    try {
      await _stagingOwner?.discardDir(dir);
    } on Object {
      // Opruimhulp mag de uitkomst nooit overschrijven.
    }
  }

  Future<void> _openDocument(
    TranscriptResult result,
    Duration duration,
    TranscriptionEngine engine,
  ) async {
    _checkTaskActive();
    final l10n = context.l10n;
    final title = stemOfFileName(widget.displayName);
    final call = _callManifest != null;
    final gaps = call ? missingCallAudio(_callManifest) : null;
    final provenance = TranscriptProvenance(
      title: title,
      sourceLabel: widget.displayName,
      recordedAt: _formatNow(),
      sourceKindLabel: call ? l10n.d('vergadering') : l10n.d('bestand'),
      durationLabel: duration > Duration.zero
          ? _formatDuration(duration)
          : null,
      engineLabel: _engineLabel(engine, l10n),
      languageCode: _language == 'auto'
          ? null
          : _language == 'mixed'
          ? l10n.d('Meerdere talen in deze opname')
          : _language,
      gapsLabel: gaps == null
          ? null
          : l10n
                .d(
                  '~{s} s bronaudio over {n} bron(nen) — track- of netwerkverlies tijdens de opname.',
                )
                .replaceAll('{s}', '${(gaps.$2.inMilliseconds / 1000).round()}')
                .replaceAll('{n}', '${gaps.$1}'),
      audioRelPath: null, // de bewaarkeuze landt bij Opslaan (§3.2)
    );
    final markdown = widget.youtubeOrigin != null
        ? youtubeTranscriptMarkdown(
            origin: widget.youtubeOrigin!,
            segments: result.segments,
            methodLabel: _engineLabel(engine, l10n) ?? '',
            processedAtLabel: _formatNow(),
            audioOffset: widget.youtubeOrigin!.start,
            language: _language == 'auto' || _language == 'mixed'
                ? null
                : _language,
            speakerLabel: l10n.d('Spreker'),
            unknownLabel: l10n.d('Onbekend'),
          )
        : buildTranscriptMarkdown(
            provenance,
            formatTranscriptBody(
              result.segments,
              speakerLabel: l10n.d('Spreker'),
              unknownLabel: l10n.d('Onbekend'),
            ),
          );
    await _discardStaging();
    _checkTaskActive();
    ref
        .read(tabsProvider.notifier)
        .newDocumentFromMarkdown(
          markdown,
          suggestedName: '$title transcript',
          // Web heeft geen `media/` bij een losse download — de checkbox
          // staat daar bewust uit, dus dit veld is daar altijd null.
          pendingAudioPath: _keepAudio && widget.youtubeOrigin == null
              ? widget.sourcePath
              : null,
        );
    if (mounted) Navigator.of(context).pop();
  }

  String? _engineLabel(TranscriptionEngine engine, AppLocalizations l10n) {
    if (engine is LocalWhisperEngine) {
      final id = engine.model?.id;
      return 'whisper.cpp ${id ?? ''} (${l10n.d('lokaal')})'.trim();
    }
    final profile = ref.read(asrServerProfileProvider);
    return '${profile.provenanceName} (${l10n.d('server')})';
  }

  void _stop() {
    _cancelRequested = true;
    _session?.cancel();
    // De instantie die de run drijft — niet een vers gelezen die de
    // provider na een route- of modelwissel eventueel opnieuw bouwde.
    _engine?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = ref.watch(asrServerProfileProvider);
    final route = ref.watch(transcriptionRouteProvider);
    final isServer = route == 'server' && profile.isConfigured;
    final engine = ref.watch(transcriptionEngineProvider);
    ref.listen<TranscriptionEngine?>(transcriptionEngineProvider, (
      previous,
      next,
    ) {
      if (_phase != _Phase.ready || identical(previous, next)) return;
      setState(() {
        _diarize = false;
        _diarizationAvailable = false;
        _languages = const ['auto'];
        _language = 'auto';
      });
      unawaited(_loadLanguages());
    });
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(l10n.d('Audio of video transcriberen')),
        content: SizedBox(
          width: 520,
          child: switch (_phase) {
            _Phase.ready => _readyContent(
              l10n,
              isServer,
              profile.host,
              engineAvailable: engine != null,
            ),
            _Phase.running => _runningContent(l10n),
            _Phase.failed => _failedContent(l10n),
          },
        ),
        actions: _actions(l10n, isServer, engineAvailable: engine != null),
      ),
    );
  }

  List<Widget> _actions(
    AppLocalizations l10n,
    bool isServer, {
    required bool engineAvailable,
  }) {
    return switch (_phase) {
      _Phase.ready => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        // Staat de module uit, dan is Instellingen de enige zinnige
        // stap — een dode Start-knop met een vaag verzoek is geen
        // uitweg (#2932).
        if (!engineAvailable)
          FilledButton(
            onPressed: () => SettingsDialog.show(
              context,
              initialSection: SettingsSection.modules,
            ),
            child: Text(l10n.d('Instellingen openen')),
          )
        else
          FilledButton(
            onPressed: _info == null || _startDisabled() ? null : _start,
            child: Text(
              isServer
                  ? l10n.d('Uploaden en transcriberen')
                  : l10n.d('Transcriberen'),
            ),
          ),
      ],
      _Phase.running => [
        TextButton(onPressed: _stop, child: Text(l10n.d('Stop'))),
      ],
      _Phase.failed => [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    };
  }

  /// De Start-knop staat uit zolang de voorbeschouwing aantoont dat het
  /// niet kan — de reden staat er dan naast.
  bool _startDisabled() {
    final info = _info;
    if (info == null) return true;
    return !info.engineReadsDirectly && !info.decodable;
  }

  Widget _readyContent(
    AppLocalizations l10n,
    bool isServer,
    String host, {
    required bool engineAvailable,
  }) {
    final info = _info;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _factRow(l10n.d('Bestand'), widget.displayName),
        if (info != null) ...[
          _factRow(l10n.d('Grootte'), _formatBytes(info.sizeBytes)),
          _factRow(l10n.d('Formaat'), _containerLabel(info.container, l10n)),
          if (info.duration != null)
            _factRow(l10n.d('Duur'), _formatDuration(info.duration!)),
          _factRow(
            l10n.d('Verwachte opslag'),
            info.engineReadsDirectly
                ? l10n.d('geen extra kopie — het bestand wordt direct gelezen')
                : '~${_formatBytes(_decodedEstimate(info))}',
          ),
          if (!info.engineReadsDirectly && info.decodeNote != null)
            _note(l10n, l10n.d(info.decodeNote!)),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Bevat het bestand andermans stemmen? Hun toestemming kan nodig zijn.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 8),
        if (!engineAvailable)
          _note(
            l10n,
            l10n.d(
              'De transcriptiemodule staat uit of is niet ingesteld. Schakel hem in via Instellingen → Modules.',
            ),
          )
        else ...[
          _routeBanner(l10n, isServer, host),
          const SizedBox(height: 8),
          _languageRow(l10n),
          if (_diarizationAvailable)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n.d('Sprekers onderscheiden'),
                style: const TextStyle(fontSize: 13),
              ),
              value: _diarize,
              onChanged: (v) => setState(() => _diarize = v ?? false),
            ),
          if (!kIsWeb && widget.youtubeOrigin == null) _keepAudioRow(l10n),
        ],
      ],
    );
  }

  Widget _routeBanner(AppLocalizations l10n, bool isServer, String host) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isServer
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isServer ? Icons.cloud_upload_outlined : Icons.lock_outline,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isServer
                  ? l10n
                        .d(
                          'De audio uit {bestand} gaat naar {host}. Niets anders verlaat dit apparaat.',
                        )
                        .replaceAll('{bestand}', widget.displayName)
                        .replaceAll('{host}', host)
                  : l10n.d(
                      'Alles blijft op dit apparaat — de audio gaat nergens heen.',
                    ),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _languageRow(AppLocalizations l10n) => Row(
    children: [
      Text('${l10n.d('Taal')}: ', style: const TextStyle(fontSize: 13)),
      Expanded(
        child: DropdownButton<String>(
          value: _language,
          isExpanded: true,
          items: [
            for (final code in _languages)
              DropdownMenuItem(
                value: code,
                child: Text(
                  switch (code) {
                    'auto' =>
                      '${l10n.d('Automatisch detecteren')} (${l10n.d('één taal')})',
                    'mixed' => l10n.d('Meerdere talen in deze opname'),
                    _ => code,
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _language = v ?? 'auto'),
        ),
      ),
    ],
  );

  Widget _keepAudioRow(AppLocalizations l10n) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(
      l10n.d('Bewaar een kopie van de audio naast het document'),
      style: const TextStyle(fontSize: 13),
    ),
    subtitle: Text(
      l10n.d('Bij Opslaan wordt hij naar media/ naast het .md gekopieerd.'),
      style: const TextStyle(fontSize: 11.5),
    ),
    value: _keepAudio,
    onChanged: (v) => setState(() => _keepAudio = v ?? false),
  );

  Widget _runningContent(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_decoding ? l10n.d('Bestand decoderen…') : l10n.d('Transcriberen…')),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: _decoding ? null : _progress),
      if (!_decoding && _progress != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${(_progress! * 100).round()}%',
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        l10n.d('Het bronbestand blijft ongewijzigd.'),
        style: TextStyle(fontSize: 12, color: AppTheme.slate600),
      ),
    ],
  );

  Widget _failedContent(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.error_outline, size: 20, color: AppTheme.red600),
      const SizedBox(height: 8),
      Text(_errorText(l10n, _error), style: const TextStyle(fontSize: 13)),
    ],
  );

  Widget _factRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: AppTheme.slate600),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5))),
      ],
    ),
  );

  Widget _note(AppLocalizations l10n, String note) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(note, style: TextStyle(fontSize: 12, color: AppTheme.amber700)),
  );

  /// De vertaling van een getypte fout naar een benoemde vervolgstap —
  /// de types uit §4.4 krijgen elk hun eigen zin.
  String _errorText(AppLocalizations l10n, Object? error) {
    return switch (error) {
      _NoSpeechFound() =>
        l10n
            .d('Geen spraak gevonden in {bestand}. Het bestand is ongewijzigd.')
            .replaceAll('{bestand}', widget.displayName),
      DecodeFailed(:final message) =>
        l10n
            .d('Het bestand kon niet worden gedecodeerd: {reden}')
            .replaceAll('{reden}', message),
      UnsupportedSource(:final message) =>
        l10n
            .d('Dit formaat kan niet op dit apparaat: {reden}')
            .replaceAll('{reden}', message),
      CapacityExceeded() => l10n.d(
        'Het bestand is te groot of de audio te lang voor deze route.',
      ),
      IoFailed(:final message) =>
        l10n
            .d('Het bestand kon niet worden gelezen: {reden}')
            .replaceAll('{reden}', message),
      EngineUnavailable(:final message) =>
        l10n
            .d('De transcriptie-engine is niet klaar: {reden}')
            .replaceAll('{reden}', message),
      ServerRefused(:final message) =>
        l10n
            .d('De server weigerde of was onbereikbaar: {reden}')
            .replaceAll('{reden}', message),
      ConsentRequired() => l10n.d(
        'De serverroute vraagt een toestemming die nog niet is bevestigd.',
      ),
      SourceUnavailable(:final message) =>
        l10n
            .d('De bron is niet beschikbaar: {reden}')
            .replaceAll('{reden}', message),
      _ => l10n.d('Er ging iets mis bij het transcriberen.'),
    };
  }

  /// Ruwe schatting van het gedecodeerde WAV (16 kHz mono ≈ 32 kB/s) —
  /// waar de duur onbekend is, de bron-grootte als bovengrens-advies.
  int _decodedEstimate(FileSourceInfo info) {
    final d = info.duration;
    if (d != null) return (d.inMilliseconds / 1000 * 32000).round();
    return info.sizeBytes;
  }

  String _containerLabel(MediaContainer c, AppLocalizations l10n) =>
      switch (c) {
        MediaContainer.wav => 'WAV',
        MediaContainer.mpeg4 => 'MP4/M4A',
        MediaContainer.ogg => 'Ogg',
        MediaContainer.flac => 'FLAC',
        MediaContainer.mp3 => 'MP3',
        MediaContainer.aac => 'ADTS/AAC',
        MediaContainer.aiff => 'AIFF/AIFC',
        MediaContainer.caf => 'CAF',
        MediaContainer.ebml => 'WebM/MKV',
        MediaContainer.avi => 'AVI',
        MediaContainer.unknown => l10n.d('onbekend'),
      };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  static String _formatNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}';
  }
}

/// "De pass vond niets" is een uitkomst, geen crash — een eigen type
/// zodat de fouttekst het bestand benoemt zonder de engine-taal na te
/// bouwen.
class _NoSpeechFound implements Exception {
  const _NoSpeechFound(this.name);
  final String name;
}
