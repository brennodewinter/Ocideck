// De duurzame microfoonfile (#2516): 16 kHz mono PCM, een header die een
// crash overleeft, en een plafond dat een buurbestand niet aanraakt.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/pcm_resample.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/wav_sink.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ocideck_wav_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  int u32(Uint8List bytes, int off) =>
      bytes[off] |
      (bytes[off + 1] << 8) |
      (bytes[off + 2] << 16) |
      (bytes[off + 3] << 24);

  test('een blok PCM wordt een afspeelbare 16 kHz-mono-WAV', () async {
    final path = '${dir.path}/$recordingWavName';
    final wav = IncrementalWav(path);
    await wav.open();
    final pcm = Uint8List(3200);
    ByteData.sublistView(pcm).setInt16(0, 1000, Endian.little);
    await wav.add(pcm);
    expect(wav.duration, const Duration(milliseconds: 100));
    await wav.close();

    final bytes = await File(path).readAsBytes();
    final info = parseWavHeader(bytes, bytes.length);
    expect(bytes.length, 44 + 3200);
    expect(u32(bytes, 4), 36 + 3200);
    expect(u32(bytes, 40), 3200);
    expect(info, isNotNull);
    expect(info!.sampleRate, recordingSampleRate);
    expect(info.channels, 1);
    expect(info.bitsPerSample, 16);
    expect(info.duration, const Duration(milliseconds: 100));
    expect(ByteData.sublistView(bytes).getInt16(44, Endian.little), 1000);
  });

  test(
    'repairWavHeader zet de lengte gelijk zonder de file te korten',
    () async {
      final path = '${dir.path}/$recordingWavName';
      final wav = IncrementalWav(path);
      await wav.open();
      await wav.add(Uint8List(100));
      await wav.close();
      final before = await File(path).length();

      final raf = await File(path).open(mode: FileMode.append);
      final zero = ByteData(4)..setUint32(0, 0, Endian.little);
      await raf.setPosition(4);
      await raf.writeFrom(zero.buffer.asUint8List());
      await raf.setPosition(40);
      await raf.writeFrom(zero.buffer.asUint8List());
      await raf.close();

      expect(await repairWavHeader(path), isTrue);
      final bytes = await File(path).readAsBytes();
      expect(bytes.length, before);
      expect(u32(bytes, 40), 100);
      expect(u32(bytes, 4), 36 + 100);
      final info = parseWavHeader(bytes, bytes.length);
      expect(info!.sampleRate, recordingSampleRate);
    },
  );

  test('repairWavHeader laat een vreemd bestand met rust', () async {
    final path = '${dir.path}/not.wav';
    await File(path).writeAsBytes(List<int>.filled(80, 7));
    expect(await repairWavHeader(path), isFalse);
    expect(await File(path).readAsBytes(), List<int>.filled(80, 7));
  });

  test('het byteplafond raakt een buurbestand niet', () async {
    final sibling = File('${dir.path}/older.wav')..writeAsBytesSync([1, 2, 3]);
    final wav = IncrementalWav('${dir.path}/$recordingWavName', maxBytes: 8);
    await wav.open();
    await wav.add(Uint8List(4));
    expect(() => wav.add(Uint8List(8)), throwsA(isA<IoFailed>()));
    expect(await sibling.readAsBytes(), [1, 2, 3]);
    expect(File(wav.path).existsSync(), isTrue);
    expect(wav.dataBytes, 4);
  });

  test('48 kHz stereo wordt 16 kHz mono, een afgekapte staart wacht', () {
    final resampler = Mono16kResampler(sampleRate: 48000, channels: 2);
    final stereo = ByteData(6 * 4);
    for (var i = 0; i < 12; i++) {
      stereo.setInt16(i * 2, 1000, Endian.little);
    }
    final out = resampler.add(stereo.buffer.asUint8List());
    expect(out.length, 4);
    final view = ByteData.sublistView(out);
    expect(view.getInt16(0, Endian.little), 1000);
    expect(view.getInt16(2, Endian.little), 1000);

    final tail = Mono16kResampler(sampleRate: 16000, channels: 1);
    expect(tail.add(Uint8List.fromList([0x34])), isEmpty);
    final rest = tail.add(Uint8List.fromList([0x12, 0x00]));
    expect(rest, [0x34, 0x12]);
    final odd = tail.add(Uint8List.fromList([0xFF]));
    expect(odd, [0x00, 0xFF]);
  });

  test('pcmRms is 0 bij stilte en 1 bij volle schaal', () {
    expect(pcmRms(Uint8List(8)), 0);
    final full = ByteData(2)..setInt16(0, -32768, Endian.little);
    expect(pcmRms(full.buffer.asUint8List()), 1);
  });
}
