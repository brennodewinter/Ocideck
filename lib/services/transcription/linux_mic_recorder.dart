// Linux-microfoon via `parecord` (#2516).
//
// PipeWire levert dat programma via pipewire-pulse, PulseAudio via
// pulseaudio-utils. Het is de binding: ruwe s16le op stdout, vaste
// sampleklok, geen shell. Zonder het programma is de route niet
// beschikbaar — we starten geen tweede, verborgen greep en we gokken
// geen ALSA-apparaatnaam.
//
// De omgeving is een toelatingslijst. Een recorder móét het
// gebruikerssessie-audiodaemon kunnen vinden (`XDG_RUNTIME_DIR`,
// `PULSE_SERVER`, de bus); de rest van de omgeving — sleutels, tokens —
// gaat niet mee.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'transcription_errors.dart';

const linuxCaptureRate = 48000;
const linuxCaptureChannels = 2;

/// Wat `describe` en `open` van het systeem willen weten, injecteerbaar
/// zodat een toets geen echte microfoon en geen `PATH` nodig heeft.
class LinuxMicTools {
  const LinuxMicTools({
    required this.parecordPath,
    required this.pactlPath,
    required this.sourcesText,
  });

  /// Absoluut pad, of null als `parecord` er niet is.
  final String? parecordPath;
  final String? pactlPath;

  /// De tekst van `pactl list sources`, of null als pactl ontbreekt.
  final String? sourcesText;
}

typedef LinuxToolLookup = Future<LinuxMicTools> Function();

class LinuxRecordPlan {
  const LinuxRecordPlan({required this.executable, required this.args});

  final String executable;
  final List<String> args;
}

/// Bouwt de argv. [deviceId] null is de systeemstandaard — dan laten we
/// `--device` weg, zodat Pulse zijn eigen default kiest. Een id die op
/// een vlag lijkt of tekens buiten de apparaatnaam draagt, wijzen we af.
LinuxRecordPlan? planLinuxRecording({
  required String? parecordPath,
  String? deviceId,
}) {
  if (parecordPath == null || parecordPath.isEmpty) return null;
  if (deviceId != null && !isSafePulseDevice(deviceId)) return null;
  return LinuxRecordPlan(
    executable: parecordPath,
    args: [
      '--raw',
      '--rate=$linuxCaptureRate',
      '--channels=$linuxCaptureChannels',
      '--format=s16le',
      '--latency-msec=50',
      if (deviceId != null) '--device=$deviceId',
    ],
  );
}

/// Pulse-bronnamen: letters, cijfers, en de leestekens die `pactl` zelf
/// in een naam zet. Geen spatie, geen aanhalingsteken, geen streepje
/// vooraan — dat laatste zou een extra vlag zijn.
bool isSafePulseDevice(String id) {
  if (id.isEmpty || id.startsWith('-')) return false;
  // Streepje midden in de naam is normaal (`usb-mic`). Alleen vooraan
  // zou het een extra vlag zijn, en dat wijst de caller hierboven af.
  return RegExp(r'^[A-Za-z0-9_.:@/-]+$').hasMatch(id);
}

class ParsedLinuxSource {
  const ParsedLinuxSource({
    required this.name,
    required this.description,
    required this.transport,
  });

  final String name;
  final String description;
  final MicTransport transport;
}

/// Leest `pactl list sources`. [monitors] false houdt de microfoons
/// (geen `.monitor`); true houdt alleen de uitvoermonitors — dat is
/// systeemgeluid (#2520), niet de microfoon.
List<ParsedLinuxSource> parsePactlSources(
  String text, {
  bool monitors = false,
}) {
  final sources = <ParsedLinuxSource>[];
  String? name;
  String? description;
  String? bus;
  void flush() {
    if (name != null && name!.endsWith('.monitor') == monitors) {
      sources.add(
        ParsedLinuxSource(
          name: name!,
          description: (description == null || description!.isEmpty)
              ? name!
              : description!,
          transport: _bus(bus),
        ),
      );
    }
    name = null;
    description = null;
    bus = null;
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('Source #')) {
      flush();
      continue;
    }
    if (line.startsWith('Name: ')) {
      name = line.substring('Name: '.length).trim();
    } else if (line.startsWith('Description: ')) {
      description = line.substring('Description: '.length).trim();
    } else if (line.startsWith('device.bus = ')) {
      bus = line.substring('device.bus = '.length).replaceAll('"', '').trim();
    }
  }
  flush();
  return sources;
}

MicTransport _bus(String? bus) => switch (bus) {
  'usb' => MicTransport.usb,
  'bluetooth' => MicTransport.bluetooth,
  'pci' => MicTransport.builtIn,
  _ => MicTransport.unknown,
};

/// De variabelen die een gebruikerssessie-audiodaemon nodig heeft, en
/// niets daarbuiten.
Map<String, String> linuxRecorderEnvironment() {
  const allow = {
    'HOME',
    'USER',
    'LOGNAME',
    'XDG_RUNTIME_DIR',
    'XDG_CONFIG_HOME',
    'PULSE_SERVER',
    'PULSE_COOKIE',
    'DBUS_SESSION_BUS_ADDRESS',
    'PIPEWIRE_RUNTIME_DIR',
    'LANG',
  };
  final env = <String, String>{'LC_ALL': 'C'};
  for (final key in allow) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) env[key] = value;
  }
  return env;
}

class LinuxMicPort extends MicCapturePort {
  LinuxMicPort({LinuxToolLookup? lookup}) : _lookup = lookup ?? _defaultLookup;

  final LinuxToolLookup _lookup;

  @override
  Future<MicPlatformFacts> describe() async {
    final tools = await _lookup();
    if (tools.parecordPath == null) {
      return const MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: 'parecord ontbreekt — pipewire-pulse of pulseaudio-utils',
      );
    }
    final inputs = <MicInput>[];
    final text = tools.sourcesText;
    if (text != null) {
      for (final source in parsePactlSources(text)) {
        inputs.add(
          MicInput(
            id: source.name,
            label: source.description,
            transport: source.transport,
          ),
        );
      }
    }
    // De matrix zegt: het echte antwoord volgt pas als de hardware
    // opengaat. Beschikbare programma's zijn nog geen open microfoon.
    return MicPlatformFacts(
      availability: CaptureAvailability.tryAfterPermission,
      inputs: inputs,
    );
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    final tools = await _lookup();
    final plan = planLinuxRecording(
      parecordPath: tools.parecordPath,
      deviceId: deviceId,
    );
    if (plan == null) {
      if (deviceId != null && !isSafePulseDevice(deviceId)) {
        throw const UnsupportedSource('apparaatnaam is niet bruikbaar');
      }
      throw const SourceUnavailable('parecord ontbreekt');
    }
    return _LinuxLive(plan);
  }
}

/// Uitvoermonitor via hetzelfde `parecord`, nooit de microfoon (#2520).
/// Zonder een `.monitor`-bron is de route afwezig — we gokken geen
/// ALSA-apparaat en we openen niet de standaardmicrofoon.
class LinuxMonitorPort extends MicCapturePort {
  LinuxMonitorPort({LinuxToolLookup? lookup})
    : _lookup = lookup ?? _defaultLookup;

  final LinuxToolLookup _lookup;

  @override
  Future<MicPlatformFacts> describe() async {
    final tools = await _lookup();
    if (tools.parecordPath == null || tools.sourcesText == null) {
      return const MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: 'geen pactl-monitor — pipewire-pulse of pulseaudio-utils',
      );
    }
    final monitors = parsePactlSources(tools.sourcesText!, monitors: true);
    if (monitors.isEmpty) {
      return const MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: 'geen uitvoermonitor',
      );
    }
    return MicPlatformFacts(
      availability: CaptureAvailability.tryAfterPermission,
      inputs: [
        for (final source in monitors)
          MicInput(
            id: source.name,
            label: source.description,
            transport: source.transport,
          ),
      ],
    );
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    final tools = await _lookup();
    final monitors = tools.sourcesText == null
        ? const <ParsedLinuxSource>[]
        : parsePactlSources(tools.sourcesText!, monitors: true);
    final id = deviceId ?? (monitors.isEmpty ? null : monitors.first.name);
    if (id == null || !id.endsWith('.monitor')) {
      throw const SourceUnavailable('geen uitvoermonitor');
    }
    final plan = planLinuxRecording(
      parecordPath: tools.parecordPath,
      deviceId: id,
    );
    if (plan == null) {
      throw const UnsupportedSource('apparaatnaam is niet bruikbaar');
    }
    return _LinuxLive(plan);
  }
}

class _LinuxLive implements MicCaptureLive {
  _LinuxLive(this._plan) {
    _start();
  }

  final LinuxRecordPlan _plan;
  final _frames = StreamController<MicPcmFrame>.broadcast();
  final _ended = StreamController<CaptureEndCause>.broadcast();
  Process? _process;
  var _stopped = false;

  @override
  MicStreamFormat get format => const MicStreamFormat(
    sampleRate: linuxCaptureRate,
    channels: linuxCaptureChannels,
  );

  @override
  Stream<MicPcmFrame> get frames => _frames.stream;

  @override
  Stream<CaptureEndCause> get ended => _ended.stream;

  Future<void> _start() async {
    try {
      final process = await Process.start(
        _plan.executable,
        _plan.args,
        environment: linuxRecorderEnvironment(),
        mode: ProcessStartMode.normal,
      );
      if (_stopped) {
        process.kill();
        return;
      }
      _process = process;
      process.stdout.listen((chunk) {
        if (!_stopped && chunk.isNotEmpty) {
          _frames.add(MicPcmFrame(Uint8List.fromList(chunk)));
        }
      });
      unawaited(
        process.exitCode.then((_) {
          // Een vroeg einde is bronverlies: apparaat weg, of parecord
          // dat de bron niet kon openen. Linux vraagt zelden een
          // toestemmingsdialoog; een weigering komt als dezelfde stop.
          if (!_stopped) _ended.add(CaptureEndCause.sourceLost);
        }),
      );
    } on ProcessException {
      if (!_stopped) _ended.add(CaptureEndCause.sourceLost);
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _process?.kill();
    _process = null;
    if (!_frames.isClosed) await _frames.close();
    if (!_ended.isClosed) await _ended.close();
  }
}

Future<LinuxMicTools> _defaultLookup() async {
  final parecord = await _which('parecord');
  final pactl = await _which('pactl');
  String? sources;
  if (pactl != null) {
    try {
      final result = await Process.run(pactl, const [
        'list',
        'sources',
      ], environment: linuxRecorderEnvironment());
      if (result.exitCode == 0) sources = result.stdout as String;
    } on ProcessException {
      sources = null;
    }
  }
  return LinuxMicTools(
    parecordPath: parecord,
    pactlPath: pactl,
    sourcesText: sources,
  );
}

Future<String?> _which(String name) async {
  try {
    final result = await Process.run('which', [name]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    if (path.isEmpty || path.contains('\n') || path.contains('\r')) {
      return null;
    }
    return path;
  } on ProcessException {
    return null;
  }
}

/// Vrije kilobytes volgens POSIX `df -P`. Null als het antwoord niet
/// te lezen is — dan beslist het schrijven zelf, niet een gok.
Future<int?> dfFreeBytes(String directory) async {
  try {
    final result = await Process.run('df', ['-Pk', directory]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.split(RegExp(r'\s+'));
    if (cols.length < 4) return null;
    final kb = int.tryParse(cols[3]);
    if (kb == null) return null;
    return kb * 1024;
  } on ProcessException {
    return null;
  }
}
