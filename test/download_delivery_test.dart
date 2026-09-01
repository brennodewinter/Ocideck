// Aflevering op web (#1902): één export hoort als één download te vertrekken.
//
// De aanleiding is niet theoretisch. Browsers laten de eerste automatische
// download door en zetten een poort voor de tweede en verdere; een geredigeerde
// export bood zijn rapport, zijn manifest en zijn sleutels apart aan, en wat
// daar tegengehouden werd zag niemand — de app meldde "geëxporteerd". Deze test
// meet wat er tot #1902 niet te meten viel: hoevéél downloads een export
// afvuurt, en of een geweigerde download ook als mislukking terugkomt.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/download_delivery.dart';

typedef _Call = ({String name, Uint8List bytes, String mime});

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final calls = <_Call>[];
  var accept = true;

  setUp(() {
    calls.clear();
    accept = true;
    debugDownloadSink = (name, bytes, mime) {
      calls.add((name: name, bytes: bytes, mime: mime));
      return accept;
    };
  });

  tearDown(() {
    debugDownloadSink = null;
    debugDeliversByDownload = null;
  });

  test('één bestand gaat als zichzelf, niet als zip', () {
    final delivered = deliverAsDownload([
      (name: 'rapport.pdf', bytes: _bytes('pdf')),
    ], bundleName: 'rapport.pdf.zip');

    expect(delivered, 'rapport.pdf');
    expect(calls, hasLength(1));
    expect(calls.single.name, 'rapport.pdf');
    expect(calls.single.mime, 'application/pdf');
  });

  test('meer dan één bestand vertrekt als één download', () {
    final delivered = deliverAsDownload([
      (name: 'rapport.pdf', bytes: _bytes('pdf')),
      (name: 'rapport-redactie.json', bytes: _bytes('{"commitments":1}')),
      (name: 'rapport-redactie-sleutels.json', bytes: _bytes('{"salts":1}')),
    ], bundleName: 'rapport.pdf.zip');

    // De kern van #1902: precies één aanroep. Drie losse downloads zou de
    // browser na de eerste stilzwijgend hebben afgekapt.
    expect(calls, hasLength(1));
    expect(delivered, 'rapport.pdf.zip');
    expect(calls.single.name, 'rapport.pdf.zip');
    expect(calls.single.mime, 'application/zip');

    final zip = ZipDecoder().decodeBytes(calls.single.bytes);
    expect(zip.files.map((f) => f.name), [
      'rapport.pdf',
      'rapport-redactie.json',
      'rapport-redactie-sleutels.json',
    ]);
    expect(utf8.decode(zip.files[1].content as List<int>), '{"commitments":1}');
  });

  test('een geweigerde download levert geen naam op', () {
    accept = false;
    expect(
      deliverAsDownload([
        (name: 'rapport.pdf', bytes: _bytes('pdf')),
      ], bundleName: 'rapport.pdf.zip'),
      isNull,
    );
    expect(
      deliverAsDownload([
        (name: 'a.md', bytes: _bytes('a')),
        (name: 'b.md', bytes: _bytes('b')),
      ], bundleName: 'sessie.zip'),
      isNull,
    );
  });

  test('zonder bestanden gebeurt er niets', () {
    expect(deliverAsDownload(const [], bundleName: 'leeg.zip'), isNull);
    expect(calls, isEmpty);
  });

  test('tekst gaat als UTF-8 de deur uit', () {
    final delivered = deliverTextAsDownload('deck.md', '# Café ☕\n');

    expect(delivered, 'deck.md');
    expect(utf8.decode(calls.single.bytes), '# Café ☕\n');
    expect(calls.single.mime, 'text/markdown;charset=utf-8');
  });

  test('de bundelnaam houdt de volledige naam van het hoofdbestand', () {
    // Niet de kale basisnaam: een PDF- en een HTML-export van hetzelfde deck
    // zouden dan dezelfde zip-naam krijgen en in een downloadmap niet meer uit
    // elkaar te houden zijn.
    expect(bundleNameFor('20260901 deck.pdf'), '20260901 deck.pdf.zip');
    expect(bundleNameFor('20260901 deck.html'), '20260901 deck.html.zip');
  });

  test('een onbekende extensie valt terug op octet-stream', () {
    deliverAsDownload([
      (name: 'deck.ocideck', bytes: _bytes('zip')),
    ], bundleName: 'x.zip');
    deliverAsDownload([
      (name: 'raar.xyzzy', bytes: _bytes('?')),
    ], bundleName: 'x.zip');

    expect(calls.first.mime, 'application/zip');
    expect(calls.last.mime, 'application/octet-stream');
  });

  test('deliversByDownload volgt de testvlag, en staat uit op de VM', () {
    expect(deliversByDownload, isFalse);
    debugDeliversByDownload = true;
    expect(deliversByDownload, isTrue);
  });
}
