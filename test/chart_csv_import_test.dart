import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/chart_csv_import.dart';
import 'package:ocideck/utils/number_convention.dart';

final class _PickedCsv extends PlatformFile {
  _PickedCsv(this.chunks, {this.reportedLength});

  final List<Uint8List> chunks;
  final int? reportedLength;
  bool streamOpened = false;
  int chunksRead = 0;

  @override
  String get name => 'chart.csv';

  @override
  Uri get uri => Uri.parse('memory:chart.csv');

  @override
  Never get xFile => throw UnsupportedError('Gebruik de begrensde stream');

  @override
  int? lengthSync() => reportedLength;

  @override
  Future<int?> length() async => reportedLength;

  @override
  Future<Uint8List> readAsBytes() =>
      throw UnsupportedError('Gebruik de begrensde stream');

  @override
  Stream<Uint8List> readAsByteStream() async* {
    streamOpened = true;
    for (final chunk in chunks) {
      chunksRead++;
      yield chunk;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const byteLimit = 2 * 1024 * 1024;

  test('CSV lezen bewaart UTF-8 die over streamchunks is verdeeld', () async {
    const csv = 'Maand,Omzet\nMärz,12.5\n';
    final bytes = utf8.encode(csv);
    final split = bytes.indexOf(0xc3) + 1;
    final file = _PickedCsv([
      Uint8List.fromList(bytes.sublist(0, split)),
      Uint8List.fromList(bytes.sublist(split)),
    ], reportedLength: bytes.length);

    expect(await readChartCsv(file), csv);
    expect(file.streamOpened, isTrue);
    expect(file.chunksRead, 2);
  });

  test('een bekende te grote CSV wordt vóór het lezen geweigerd', () async {
    final file = _PickedCsv([], reportedLength: byteLimit + 1);

    await expectLater(readChartCsv(file), throwsFormatException);
    expect(file.streamOpened, isFalse);
    expect(file.chunksRead, 0);
  });

  test('een onbekende lengte kan de bytegrens niet omzeilen', () async {
    final file = _PickedCsv([
      Uint8List(byteLimit),
      Uint8List.fromList([65]),
      Uint8List.fromList([66]),
    ]);

    await expectLater(readChartCsv(file), throwsFormatException);
    expect(file.chunksRead, 2, reason: 'na de overschrijding stopt het lezen');
  });

  test('een CSV van precies 2 MiB blijft toegestaan', () async {
    final bytes = Uint8List(byteLimit)..fillRange(0, byteLimit, 65);
    final result = await readChartCsv(
      _PickedCsv([bytes], reportedLength: byteLimit),
    );

    expect(result, hasLength(byteLimit));
    expect(result, startsWith('AAA'));
  });

  test('ongeldige UTF-8 wordt niet stilzwijgend vervangen', () async {
    final file = _PickedCsv([
      Uint8List.fromList([0xc3, 0x28]),
    ]);
    await expectLater(readChartCsv(file), throwsFormatException);
  });

  const ambiguousCsv = 'Maand,Omzet\nJanuari,"1,234"\nFebruari,"2,345"\n';

  test(
    'de parse-isolate bewaart onbesliste getallen voor de gebruiker',
    () async {
      final result = await parseChartCsv(ambiguousCsv);

      expect(result.$1, ['Januari', 'Februari']);
      expect(result.$2.single.name, 'Omzet');
      expect(result.$2.single.data, [0.0, 0.0]);
      expect(result.ambiguous, ['1,234', '2,345']);
      expect(result.unreadable, isEmpty);
    },
  );

  test('de gekozen decimale conventie bereikt de parse-isolate', () async {
    for (final (convention, expected) in [
      (DecimalConvention.comma, [1.234, 2.345]),
      (DecimalConvention.dot, [1234.0, 2345.0]),
    ]) {
      final result = await parseChartCsv(ambiguousCsv, convention: convention);
      expect(result.$2.single.data, expected, reason: convention.name);
      expect(result.ambiguous, isEmpty);
      expect(result.unreadable, isEmpty);
    }
  });

  test('onleesbare waarden blijven als diagnostiek beschikbaar', () async {
    final result = await parseChartCsv('Maand,Omzet\nA,onleesbaar\nB,2\n');

    expect(result.$2.single.data, [0.0, 2.0]);
    expect(result.unreadable, ['onleesbaar']);
    expect(result.ambiguous, isEmpty);
  });

  test('de parse-isolate begrenst het aantal CSV-cellen', () async {
    final csv = 'Maand,Omzet\n${List.filled(50001, 'A,1').join('\n')}';
    await expectLater(parseChartCsv(csv), throwsFormatException);
  });
}
