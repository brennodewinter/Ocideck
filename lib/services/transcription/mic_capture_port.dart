// De dunne naad tussen de opnamebron en het platform (#2516).
//
// `describe` mag nooit een toestemmingsprompt tonen of een apparaat
// openen. `open` is de enige call die dat wel mag, en alleen omdat de
// gebruiker op een knop drukte. De bytes die terugkomen zijn het ruwe
// formaat van het apparaat; de bron hermonstert ze naar 16 kHz mono.
import 'dart:async';
import 'dart:typed_data';

import 'capture_source.dart';

/// Hoe het apparaat aan de machine hangt, voor zover het OS dat zegt.
/// `unknown` blijft kiesbaar — een naam die we niet herkennen is geen
/// reden om de invoer te verbergen.
enum MicTransport { builtIn, usb, bluetooth, unknown }

class MicInput {
  const MicInput({
    required this.id,
    required this.label,
    required this.transport,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final MicTransport transport;
  final bool isDefault;

  static MicInput? fromMap(Map<Object?, Object?> raw) {
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.isEmpty || label is! String || label.isEmpty) {
      return null;
    }
    return MicInput(
      id: id,
      label: label,
      transport: _transport(raw['transport']),
      isDefault: raw['isDefault'] == true,
    );
  }
}

MicTransport _transport(Object? raw) => switch (raw) {
  'builtIn' => MicTransport.builtIn,
  'usb' => MicTransport.usb,
  'bluetooth' => MicTransport.bluetooth,
  _ => MicTransport.unknown,
};

/// Wat `describe` weet zonder iets te openen.
class MicPlatformFacts {
  const MicPlatformFacts({
    required this.availability,
    this.reason,
    this.inputs = const [],
  });

  final CaptureAvailability availability;

  /// Diagnose voor logs en de instellingenrij, geen vertaalde zin.
  final String? reason;
  final List<MicInput> inputs;

  static MicPlatformFacts fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return const MicPlatformFacts(
        availability: CaptureAvailability.unavailable,
        reason: 'lege platformbeschrijving',
      );
    }
    final availability = switch (raw['availability']) {
      'available' => CaptureAvailability.available,
      'tryAfterPermission' => CaptureAvailability.tryAfterPermission,
      'untested' => CaptureAvailability.untested,
      _ => CaptureAvailability.unavailable,
    };
    final inputs = <MicInput>[];
    final listed = raw['inputs'];
    if (listed is List) {
      for (final item in listed) {
        if (item is Map) {
          final parsed = MicInput.fromMap(Map<Object?, Object?>.from(item));
          if (parsed != null) inputs.add(parsed);
        }
      }
    }
    final reason = raw['reason'];
    return MicPlatformFacts(
      availability: availability,
      reason: reason is String ? reason : null,
      inputs: inputs,
    );
  }
}

/// Eén blok ruwe invoer, in het formaat dat [MicCaptureLive.format] noemde.
class MicPcmFrame {
  const MicPcmFrame(this.pcm);

  /// Interleaved little-endian s16.
  final Uint8List pcm;
}

class MicStreamFormat {
  const MicStreamFormat({required this.sampleRate, required this.channels});

  final int sampleRate;
  final int channels;
}

/// Een geopende invoer. `stop` geeft het apparaat vrij en is idempotent.
abstract class MicCaptureLive {
  MicStreamFormat get format;
  Stream<MicPcmFrame> get frames;

  /// Eén gebeurtenis als het platform de invoer zelf beëindigt.
  Stream<CaptureEndCause> get ended;

  Future<void> stop();
}

abstract class MicCapturePort {
  const MicCapturePort();

  /// Geen prompt, geen open apparaat.
  Future<MicPlatformFacts> describe();

  /// Mag om toestemming vragen. [deviceId] null is de systeemstandaard.
  Future<MicCaptureLive> open({String? deviceId});
}
