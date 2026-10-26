// Systeemgeluid of de combinatie met de microfoon. De deelnemersmelding
// staat in dit venster; Opnemen bevestigt haar. De bron vraagt zelf pas
// om toestemming als de opname start.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/capture_source.dart';
import '../../services/transcription/desktop_mic_source.dart';
import '../../services/transcription/mic_capture_port.dart';
import '../../services/transcription/transcription_engine.dart';
import '../../services/transcription/transcription_errors.dart';
import '../../services/transcription/web_media_source.dart';
import '../../state/transcription_provider.dart';
import '../../theme/app_theme.dart';
import 'live_server_opt_in.dart';

enum RecordTarget { system, combination }

class RecordSystemDialog extends ConsumerStatefulWidget {
  const RecordSystemDialog({super.key, required this.target});

  final RecordTarget target;

  @override
  ConsumerState<RecordSystemDialog> createState() => _RecordSystemDialogState();
}

class _RecordSystemDialogState extends ConsumerState<RecordSystemDialog> {
  CaptureAvailability? _availability;
  List<MicInput> _inputs = const [];
  String? _deviceId;
  Object? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  CaptureSourceKind get _kind => widget.target == RecordTarget.combination
      ? CaptureSourceKind.combination
      : CaptureSourceKind.systemAudio;

  LiveOptInState _live = const LiveOptInState();

  Future<void> _load() async {
    final source = ref.read(captureSourcesProvider)[_kind];
    if (source == null) {
      if (mounted) {
        setState(() => _availability = CaptureAvailability.unavailable);
      }
      return;
    }
    try {
      final availability = await source.probe();
      var inputs = const <MicInput>[];
      if (source is DesktopMicrophoneSource &&
          widget.target == RecordTarget.system) {
        inputs = (await source.describe()).inputs;
      }
      if (!mounted) return;
      setState(() {
        _availability = availability;
        _inputs = inputs;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  bool get _canStart {
    final availability = _availability;
    if (_busy || availability == null) return false;
    return availability == CaptureAvailability.available ||
        availability == CaptureAvailability.tryAfterPermission;
  }

  Future<void> _start() async {
    final source = ref.read(captureSourcesProvider)[_kind];
    if (source == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(recordingSessionProvider.notifier)
          .start(
            source,
            kinds: widget.target == RecordTarget.combination
                ? const {
                    CaptureSourceKind.microphone,
                    CaptureSourceKind.systemAudio,
                  }
                : const {CaptureSourceKind.systemAudio},
            consent: const RecordingConsent(
              participantNoticeAcknowledged: true,
            ),
            inputDeviceId: _deviceId,
            liveConsent: _live.chosen
                ? ServerConsent.liveSession(_live.host)
                : null,
          );
      if (mounted) Navigator.of(context).pop();
    } on TranscriptionError catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.target == RecordTarget.combination
        ? l10n.d('Microfoon en systeemgeluid opnemen')
        : (kIsWeb
              ? l10n.d('Tabgeluid opnemen')
              : l10n.d('Systeemgeluid opnemen'));
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d('Opnemen van anderen kan hun toestemming vragen.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.target == RecordTarget.combination
                  ? l10n.d(
                      '16 kHz, stereo. Links de microfoon, rechts het systeemgeluid.',
                    )
                  : l10n.d(
                      'Dit neemt het geluid van dit apparaat op, niet een gesprek in een andere app.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            if (_availability == null && _error == null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_inputs.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: _deviceId ?? '',
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(l10n.d('Systeemstandaard')),
                  ),
                  for (final input in _inputs)
                    DropdownMenuItem(value: input.id, child: Text(input.label)),
                ],
                onChanged: (value) => setState(() {
                  _deviceId = (value == null || value.isEmpty) ? null : value;
                }),
              ),
            ],
            if (_availability == CaptureAvailability.unavailable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  kIsWeb && widget.target == RecordTarget.system
                      ? l10n.d('Tabgeluid is in deze browser niet beschikbaar.')
                      : l10n.d(
                          'Systeemgeluid is op deze opstelling niet beschikbaar.',
                        ),
                  style: TextStyle(color: AppTheme.dangerFg),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText(_error!, l10n),
                  style: TextStyle(color: AppTheme.dangerFg),
                ),
              ),
            LiveServerOptIn(
              sourcesLabel: widget.target == RecordTarget.combination
                  ? '${l10n.d('de microfoon')} + ${l10n.d('het systeemgeluid')}'
                  : l10n.d('het systeemgeluid'),
              onChanged: (state) => _live = state,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: _canStart ? _start : null,
          child: Text(l10n.d('Opnemen')),
        ),
      ],
    );
  }

  String _errorText(Object error, AppLocalizations l10n) {
    if (error is PermissionDenied) {
      return l10n.d(
        'Geef OciDeck toegang tot systeemgeluid in de systeeminstellingen.',
      );
    }
    if (error is SourceUnavailable &&
        error.message == webDisplaySilentMessage) {
      return l10n.d(
        'Het tabblad deelde geen geluid. Kies een tab en vink het geluid aan.',
      );
    }
    if (error is CapacityExceeded) {
      return l10n.d(
        'Er is te weinig vrije schijfruimte om een opname te starten. Eerder afgeronde opnames blijven staan.',
      );
    }
    return l10n.d('Het systeemgeluid kon niet worden opgenomen');
  }
}
