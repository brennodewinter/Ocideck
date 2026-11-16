import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';

void main() {
  test('media-magic wint van de tekstnaam (#2932)', () {
    final ftyp = Uint8List.fromList([0,0,0,24,...'ftypisom'.codeUnits]);
    expect(classifyOpenTarget(ftyp, extension: '.md'), OpenTarget.media);
    expect(classifyOpenTarget(ftyp, extension: '.mp3'), OpenTarget.media);
  });
  test('tekst met media-extensie blijft tekst (#2932)', () {
    final tekst = Uint8List.fromList('# deck\n\ntekst'.codeUnits);
    expect(classifyOpenTarget(tekst, extension: '.mp3'), OpenTarget.other);
    expect(classifyOpenTarget(tekst, extension: '.md'), OpenTarget.other);
  });
  test('onbekende binaire inhoud met media-naam: media-route, decoder beslist', () {
    final binair = Uint8List.fromList([1,2,3,0,9,8,7,6]);
    expect(classifyOpenTarget(binair, extension: '.mp4'), OpenTarget.media);
    expect(classifyOpenTarget(binair, extension: '.xyz'), OpenTarget.other);
  });
}
