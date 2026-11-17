import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/asr_server_profile.dart';
import '../../services/media/downloaded_media.dart';
import '../../services/media/timed_captions.dart';
import '../../services/media/youtube_reference.dart';
import '../../services/media/youtube_source_client.dart';
import '../../services/media/media_transcript.dart';
import '../../services/transcription/transcription_errors.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../state/transcription_provider.dart';
import '../../utils/literal_loopback.dart';
import '../dialogs/settings_dialog.dart';
import '../dialogs/transcribe_file_dialog.dart';
import 'youtube_source_messages.dart';

typedef YoutubeClientFactory =
    YoutubeSourceClient Function(
      AsrServerProfile destination,
      bool Function() mayUseNetwork,
      String? apiKey,
    );

/// Both explicit URL-open and a requested deck action enter this dialog.
/// Showing it only recognises a local reference; it does not start a fetch.
Future<void> showYoutubeSourceDialog(
  BuildContext context,
  YoutubeReference reference, {
  String? title,
}) => showDialog<void>(
  context: context,
  builder: (_) => YoutubeSourceDialog(reference: reference, title: title),
);

class YoutubeSourceDialog extends ConsumerStatefulWidget {
  const YoutubeSourceDialog({
    super.key,
    required this.reference,
    this.title,
    this.clientFactory,
  });
  final YoutubeReference reference;
  final String? title;
  final YoutubeClientFactory? clientFactory;

  @override
  ConsumerState<YoutubeSourceDialog> createState() =>
      _YoutubeSourceDialogState();
}

class _YoutubeSourceDialogState extends ConsumerState<YoutubeSourceDialog> {
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _language = TextEditingController();
  late final TextEditingController _start;
  late final TextEditingController _end;
  YoutubeSourceClient? _client;
  YoutubeSourceMetadata? _metadata;
  YoutubeSourceConsent? _consent;
  String? _trackId;
  Object? _error;
  bool _busy = false;
  bool _fragment = false;

  @override
  void initState() {
    super.initState();
    _start = TextEditingController(
      text: '${widget.reference.proposedStartMs / 1000}',
    );
    _end = TextEditingController(
      text: widget.reference.proposedEndMs == 0
          ? ''
          : '${widget.reference.proposedEndMs / 1000}',
    );
  }

  @override
  void dispose() {
    _client?.cancel();
    _endpoint.dispose();
    _key.dispose();
    _language.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  bool _networkAllowed() =>
      mounted &&
      ref.read(transcriptionEnabledProvider) &&
      ref.read(settingsProvider).allowRemoteMedia;

  Duration? _seconds(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0 && value <= 48 * 3600
        ? Duration(milliseconds: (value * 1000).round())
        : null;
  }

  bool get _windowValid =>
      !_fragment ||
      (_seconds(_start.text) != null &&
          (_end.text.trim().isEmpty ||
              (_seconds(_end.text) != null &&
                  _seconds(_end.text)! > _seconds(_start.text)!)));

  YoutubeTranscriptOrigin get _origin {
    if (!_windowValid) throw const DecodeFailed('ongeldige fragmentgrenzen');
    return YoutubeTranscriptOrigin(
      reference: widget.reference,
      title: _metadata?.title ?? widget.title ?? widget.reference.videoId,
      start: _fragment ? _seconds(_start.text)! : Duration.zero,
      end: _fragment && _end.text.trim().isNotEmpty
          ? _seconds(_end.text)
          : null,
    );
  }

  Future<void> _task(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _task(() async {
    if (!_networkAllowed()) return;
    _client?.cancel();
    final endpoint = _endpoint.text.trim();
    final host = Uri.tryParse(endpoint)?.host ?? '';
    final profile = AsrServerProfile(
      enabled: true,
      baseUrl: endpoint,
      mode: host == 'localhost' || isLiteralLoopbackHost(host)
          ? AsrServerMode.loopback
          : AsrServerMode.cloud,
      cloudConfirmed: true,
    );
    final factory = widget.clientFactory;
    _client = factory == null
        ? YoutubeSourceClient(
            destination: profile,
            mayUseNetwork: _networkAllowed,
            apiKey: _key.text.trim(),
          )
        : factory(profile, _networkAllowed, _key.text.trim());
    _consent = YoutubeSourceConsent(
      destination: endpoint,
      videoId: widget.reference.videoId,
    );
    final metadata = await _client!.metadata(widget.reference, _consent!);
    if (!mounted || !_networkAllowed()) return;
    setState(() {
      _metadata = metadata;
      _trackId = metadata.tracks.isEmpty ? null : metadata.tracks.first.id;
    });
  });

  Future<void> _captions() => _task(() async {
    final track = _metadata!.tracks.firstWhere((t) => t.id == _trackId);
    final result = await _client!.captions(widget.reference, track, _consent!);
    if (!mounted || !_networkAllowed()) return;
    _openCaptions(
      result.text,
      language: track.language,
      automatic: track.automatic,
      method: track.automatic
          ? context.l10n.d('Automatische ondertitels')
          : context.l10n.d('Handmatige ondertitels'),
    );
  });

  void _openCaptions(
    String text, {
    required String method,
    String? language,
    bool automatic = false,
  }) {
    final segments = parseTimedCaptions(text, rolling: automatic);
    final markdown = mediaTranscriptMarkdown(
      origin: _origin,
      segments: segments,
      methodLabel: method,
      processedAtLabel: DateTime.now().toIso8601String(),
      language: language,
    );
    ref
        .read(tabsProvider.notifier)
        .newDocumentFromMarkdown(
          markdown,
          suggestedName: '${_origin.title} transcript',
        );
    Navigator.of(context).pop();
  }

  Future<void> _importCaptions() => _task(() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vtt', 'srt'],
      dialogTitle: context.l10n.d('Kies een ondertitelbestand'),
    );
    if (picked.isEmpty || !mounted || !ref.read(transcriptionEnabledProvider)) {
      return;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in picked.first.readAsByteStream()) {
      if (!mounted || !ref.read(transcriptionEnabledProvider)) {
        throw const Cancelled('ondertitelimport geannuleerd');
      }
      if (chunk.length > 2 * 1024 * 1024 - bytes.length) {
        throw const CapacityExceeded('ondertitels zijn te groot');
      }
      bytes.add(chunk);
    }
    if (!mounted || !ref.read(transcriptionEnabledProvider)) return;
    _openCaptions(
      utf8.decode(bytes.takeBytes()),
      method: context.l10n.d('Geïmporteerde ondertitels'),
      language: _language.text.trim().isEmpty ? null : _language.text.trim(),
    );
  });

  Future<void> _audio() => _task(() async {
    final origin = _origin;
    final result = await _client!.audio(
      widget.reference,
      _consent!,
      startMs: _metadata!.audioFragments ? origin.start.inMilliseconds : 0,
      endMs: _metadata!.audioFragments ? origin.end?.inMilliseconds ?? 0 : 0,
    );
    if (!mounted || !_networkAllowed()) return;
    final media = await stageDownloadedMedia(result.bytes, result.extension);
    try {
      if (!mounted || !_networkAllowed()) return;
      await showTranscribeFileDialog(
        context,
        sourcePath: media.path,
        displayName: _origin.title,
        mediaOrigin: origin,
        mediaAudioOffset: result.sourceOffset,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      await media.release();
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = ref.watch(transcriptionEnabledProvider);
    final online = ref.watch(
      settingsProvider.select((s) => s.allowRemoteMedia),
    );
    ref.listen<bool>(transcriptionEnabledProvider, (_, next) {
      if (!next) _client?.cancel();
    });
    ref.listen<bool>(settingsProvider.select((s) => s.allowRemoteMedia), (
      _,
      next,
    ) {
      if (!next) _client?.cancel();
    });
    return AlertDialog(
      title: Text(l10n.d('Deze video transcriberen?')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(widget.reference.canonicalUrl.toString()),
              Text(l10n.d('Niet getest')),
              const SizedBox(height: 12),
              if (!enabled) ...[
                Text(
                  l10n.d(
                    'De transcriptiemodule staat uit of is niet ingesteld. Schakel hem in via Instellingen → Modules.',
                  ),
                ),
                TextButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: Text(l10n.d('Instellingen openen')),
                ),
              ] else ...[
                _fragmentChoice(l10n),
                if (!online)
                  TextButton(
                    onPressed: () => SettingsDialog.show(context),
                    child: Text(l10n.d('Online media staat uit — aanzetten')),
                  ),
                if (_metadata == null)
                  _setup(l10n, online)
                else
                  _choices(l10n, online),
                const Divider(),
                TextField(
                  controller: _language,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l10n.d('Taal')),
                ),
                TextButton.icon(
                  onPressed: _busy || !_windowValid ? null : _importCaptions,
                  icon: const Icon(Icons.subtitles_outlined),
                  label: Text(l10n.d('Ondertitels importeren…')),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    youtubeSourceError(l10n, _error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _client?.cancel();
            Navigator.of(context).pop();
          },
          child: Text(l10n.t('cancel')),
        ),
      ],
    );
  }

  Widget _fragmentChoice(AppLocalizations l10n) => Column(
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _fragment,
        onChanged: _busy
            ? null
            : (value) => setState(() => _fragment = value ?? false),
        title: Text(l10n.d('Alleen dit fragment')),
      ),
      if (_fragment)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _start,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.d('Begin (sec)')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _end,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.d('Einde (sec)'),
                  hintText: l10n.d('einde'),
                ),
              ),
            ),
          ],
        ),
      if (!_windowValid)
        Text(
          l10n.d('Ongeldige fragmentgrenzen.'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );

  Widget _setup(AppLocalizations l10n, bool online) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.d(
          'Een eigen bronserver haalt de video bij YouTube op. Ophalen stuurt de videolink naar deze server. Zonder server kunt u ondertitels importeren.',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('youtube-source-endpoint'),
        controller: _endpoint,
        enabled: !_busy && online,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l10n.d('Bronserver-URL'),
          hintText: l10n.d('https://...'),
        ),
      ),
      TextField(
        controller: _key,
        enabled: !_busy && online,
        obscureText: true,
        decoration: InputDecoration(
          labelText: l10n.d('API-sleutel (optioneel)'),
        ),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _busy || !online ? null : _load,
        child: Text(l10n.d('Video-informatie ophalen')),
      ),
    ],
  );

  Widget _choices(AppLocalizations l10n, bool online) {
    final metadata = _metadata!;
    final tracks = metadata.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metadata.title, style: Theme.of(context).textTheme.titleMedium),
        Text(sourceTimeLabel(metadata.duration)),
        if (tracks.isNotEmpty) ...[
          DropdownButton<String>(
            key: const ValueKey('youtube-caption-track'),
            value: _trackId,
            isExpanded: true,
            items: [
              for (final track in tracks)
                DropdownMenuItem(
                  value: track.id,
                  child: Text(
                    '${track.language} · '
                    '${track.automatic ? l10n.d('Automatische ondertitels') : l10n.d('Handmatige ondertitels')}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _trackId = value),
          ),
          ElevatedButton(
            onPressed: _busy || !online || !_windowValid ? null : _captions,
            child: Text(l10n.d('Ondertitels overnemen')),
          ),
        ],
        if (metadata.audioAvailable) ...[
          Text(
            l10n.d(
              'Audio downloaden opent de transcriptiekeuze. Een fragment wordt vóór ASR geknipt. De gedownloade bron wordt daarna verwijderd.',
            ),
          ),
          TextButton(
            onPressed: _busy || !online || !_windowValid ? null : _audio,
            child: Text(l10n.d('Audio downloaden en transcriberen…')),
          ),
        ],
      ],
    );
  }
}
