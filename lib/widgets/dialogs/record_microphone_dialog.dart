// Microfoon opnemen (#2516). De kiezer, de deelnemersmelding en de
// niveautest zitten vóór de start. De opname zelf loopt daarna in de
// indicator; dit venster gaat dicht zodra die loopt.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/capture_source.dart';
import '../../services/transcription/mic_capture_port.dart';
import '../../services/transcription/mic_session_gate.dart';
import '../../services/transcription/pcm_resample.dart';
import '../../services/transcription/staged_recordings.dart';
import '../../services/transcription/transcription_errors.dart';
import '../../state/transcription_provider.dart';
import '../../theme/app_theme.dart';
import 'transcribe_file_dialog.dart';

class RecordMicrophoneDialog extends ConsumerStatefulWidget {
  const RecordMicrophoneDialog({super.key});

  @override
  ConsumerState<RecordMicrophoneDialog> createState() =>
      _RecordMicrophoneDialogState();
}

class _RecordMicrophoneDialogState
    extends ConsumerState<RecordMicrophoneDialog> {
  MicPlatformFacts? _facts;
  List<StagedMicRecording> _earlier = const [];
  Object? _error;
  String? _deviceId;
  var _testing = false;
  var _level = 0.0;
  MicSessionGate? _heldGate;
  MicCaptureLive? _testLive;
  Timer? _testTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    final live = _testLive;
    _testLive = null;
    // Ook als `open` nog niet terug is: de poort is dan al van ons,
    // en `ref` mag na dispose niet meer.
    _releaseGate();
    if (live != null) unawaited(live.stop());
    super.dispose();
  }

  void _releaseGate() {
    final held = _heldGate;
    if (held == null) return;
    _heldGate = null;
    held.release(MicHolder.recording);
  }

  Future<void> _releaseTest(MicCaptureLive live) async {
    await live.stop();
    _releaseGate();
  }

  Future<void> _load() async {
    try {
      final facts = await ref.read(micCapturePortProvider).describe();
      final earlier = await listStagedMicRecordings(
        ref.read(recordingStagingProvider),
      );
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _earlier = earlier;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool get _canStart {
    final facts = _facts;
    if (facts == null || _testing) return false;
    return facts.availability == CaptureAvailability.available ||
        facts.availability == CaptureAvailability.tryAfterPermission;
  }

  Future<void> _test() async {
    final gate = ref.read(micSessionGateProvider);
    if (!gate.tryAcquire(MicHolder.recording)) {
      setState(() => _error = const SourceUnavailable(micHeldByMonitorMessage));
      return;
    }
    _heldGate = gate;
    setState(() {
      _testing = true;
      _error = null;
      _level = 0;
    });
    try {
      final live = await ref
          .read(micCapturePortProvider)
          .open(deviceId: _deviceId);
      if (!mounted) {
        await live.stop();
        _releaseGate();
        return;
      }
      _testLive = live;
      final sub = live.frames.listen((frame) {
        if (!mounted) return;
        setState(() => _level = pcmRms(frame.pcm));
      });
      _testTimer = Timer(const Duration(milliseconds: 1500), () async {
        await sub.cancel();
        await _endTest();
      });
    } on TranscriptionError catch (e) {
      _releaseGate();
      if (mounted) {
        setState(() {
          _testing = false;
          _error = e;
        });
      }
    } on Object {
      _releaseGate();
      if (mounted) {
        setState(() {
          _testing = false;
          _error = const SourceUnavailable('microfoon openen mislukt');
        });
      }
    }
  }

  Future<void> _endTest() async {
    final live = _testLive;
    _testLive = null;
    if (live != null) await _releaseTest(live);
    if (mounted) {
      setState(() {
        _testing = false;
        _level = 0;
      });
    }
  }

  Future<void> _start() async {
    final source = ref.read(
      captureSourcesProvider,
    )[CaptureSourceKind.microphone];
    if (source == null) {
      setState(
        () => _error = const SourceUnavailable(
          'geen microfoonroute op dit platform',
        ),
      );
      return;
    }
    try {
      await ref
          .read(recordingSessionProvider.notifier)
          .start(
            source,
            kinds: const {CaptureSourceKind.microphone},
            consent: const RecordingConsent(
              participantNoticeAcknowledged: true,
            ),
            inputDeviceId: _deviceId,
          );
      if (mounted) Navigator.of(context).pop();
    } on TranscriptionError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _transcribe(StagedMicRecording recording) async {
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      DialogRoute<void>(
        context: context,
        builder: (_) => TranscribeFileDialog(
          sourcePath: recording.wavPath,
          displayName: _stamp(recording.recordedAt),
        ),
      ),
    );
  }

  Future<void> _discard(StagedMicRecording recording) async {
    await ref.read(recordingStagingProvider).discardDir(recording.sessionDir);
    if (!mounted) return;
    setState(() {
      _earlier = [
        for (final item in _earlier)
          if (item.sessionDir != recording.sessionDir) item,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final facts = _facts;
    return AlertDialog(
      title: Text(l10n.d('Microfoon opnemen')),
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
              l10n.d(
                '16 kHz, mono, PCM. Dit is de microfoon in de kamer, niet het geluid van een andere app.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 12),
            if (facts == null && _error == null)
              const LinearProgressIndicator()
            else if (facts != null) ...[
              DropdownButton<String>(
                isExpanded: true,
                value: _deviceId ?? '',
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(l10n.d('Systeemstandaard')),
                  ),
                  for (final input in facts.inputs)
                    DropdownMenuItem(
                      value: input.id,
                      child: Text(_inputLabel(input, l10n)),
                    ),
                ],
                onChanged: _testing
                    ? null
                    : (value) => setState(() {
                        _deviceId = (value == null || value.isEmpty)
                            ? null
                            : value;
                      }),
              ),
              if (_testing) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _level.clamp(0.02, 1)),
                Text(
                  l10n.d('De test stopt vanzelf. Er wordt nog niets bewaard.'),
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText(_error!, l10n),
                style: TextStyle(color: AppTheme.dangerFg),
              ),
            ],
            if (_earlier.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.d('Eerdere opnames'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final recording in _earlier.take(5))
                _earlierRow(l10n, recording),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        if (!kIsWeb)
          TextButton(
            onPressed: _canStart ? _test : null,
            child: Text(l10n.d('Niveau testen')),
          ),
        FilledButton(
          onPressed: _canStart ? _start : null,
          child: Text(l10n.d('Opnemen')),
        ),
      ],
    );
  }

  Widget _earlierRow(AppLocalizations l10n, StagedMicRecording recording) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_stamp(recording.recordedAt)} · ${_clock(recording.duration)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () => _transcribe(recording),
          child: Text(l10n.d('Nu transcriberen')),
        ),
        TextButton(
          onPressed: () => _discard(recording),
          child: Text(l10n.d('Opname weggooien')),
        ),
      ],
    );
  }

  String _inputLabel(MicInput input, AppLocalizations l10n) {
    final transport = switch (input.transport) {
      MicTransport.builtIn => l10n.d('ingebouwd'),
      MicTransport.usb => l10n.d('USB'),
      MicTransport.bluetooth => l10n.d('Bluetooth'),
      MicTransport.unknown => null,
    };
    if (transport == null) return input.label;
    return '${input.label} ($transport)';
  }

  String _errorText(Object error, AppLocalizations l10n) {
    if (error is SourceUnavailable &&
        error.message == micHeldByMonitorMessage) {
      return l10n.d(
        'De presentatie-doorvoer gebruikt de microfoon al. Zet die eerst uit — twee sessies tegelijk zouden rondzingen.',
      );
    }
    if (error is PermissionDenied) {
      return l10n.d(
        'Geef OciDeck toegang tot de microfoon in de systeeminstellingen, en controleer dat er een invoerapparaat is aangesloten.',
      );
    }
    if (error is CapacityExceeded) {
      return l10n.d(
        'Er is te weinig vrije schijfruimte om een opname te starten. Eerder afgeronde opnames blijven staan.',
      );
    }
    return l10n.d('De microfoon kon niet worden aangeschakeld');
  }
}

String _stamp(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

String _clock(Duration d) {
  final total = d.inSeconds;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
