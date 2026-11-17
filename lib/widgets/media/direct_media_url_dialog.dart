import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../services/media/downloaded_media.dart';
import '../../services/media/media_transcript.dart';
import '../../services/media/media_url_client.dart';
import '../../state/settings_provider.dart';
import '../../state/transcription_provider.dart';
import '../dialogs/settings_dialog.dart';
import '../dialogs/transcribe_file_dialog.dart';
import 'youtube_source_messages.dart';

Future<void> showDirectMediaUrlDialog(BuildContext context, Uri source) =>
    showDialog<void>(
      context: context,
      builder: (_) => DirectMediaUrlDialog(source: source),
    );

class DirectMediaUrlDialog extends ConsumerStatefulWidget {
  const DirectMediaUrlDialog({super.key, required this.source});
  final Uri source;
  @override
  ConsumerState<DirectMediaUrlDialog> createState() =>
      _DirectMediaUrlDialogState();
}

class _DirectMediaUrlDialogState extends ConsumerState<DirectMediaUrlDialog> {
  MediaUrlClient? _client;
  bool _busy = false;
  Object? _error;
  bool _allowed() =>
      mounted &&
      ref.read(transcriptionEnabledProvider) &&
      ref.read(settingsProvider).allowRemoteMedia;

  @override
  void dispose() {
    _client?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    if (!_allowed()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = MediaUrlClient(mayUseNetwork: _allowed);
    _client = client;
    try {
      final result = await client.download(widget.source);
      if (!_allowed()) return;
      final media = await stageDownloadedMedia(result.bytes, result.extension);
      try {
        if (!mounted || !_allowed()) return;
        final source = widget.source.replace(
          userInfo: '',
          query: '',
          fragment: '',
        );
        final name = p.basename(source.path);
        await showTranscribeFileDialog(
          context,
          sourcePath: media.path,
          displayName: name,
          mediaOrigin: UrlTranscriptOrigin(source, title: name),
        );
        if (mounted) Navigator.of(context).pop();
      } finally {
        await media.release();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      title: Text(l10n.d('Audio of video transcriberen')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.source
                    .replace(userInfo: '', query: '', fragment: '')
                    .toString(),
              ),
              const SizedBox(height: 12),
              if (!enabled)
                Text(
                  l10n.d(
                    'De transcriptiemodule staat uit of is niet ingesteld. Schakel hem in via Instellingen → Modules.',
                  ),
                ),
              if (!online) Text(l10n.d('Online media staat uit — aanzetten')),
              if (!enabled || !online)
                TextButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: Text(l10n.d('Instellingen openen')),
                ),
              if (enabled && online)
                Text(
                  l10n.d(
                    'Audio downloaden opent de transcriptiekeuze. Een fragment wordt vóór ASR geknipt. De gedownloade bron wordt daarna verwijderd.',
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  youtubeSourceError(l10n, _error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        if (enabled && online)
          FilledButton(
            onPressed: _busy ? null : _download,
            child: Text(l10n.d('Ophalen')),
          ),
      ],
    );
  }
}
