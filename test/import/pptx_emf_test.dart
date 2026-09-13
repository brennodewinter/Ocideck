import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/import/importers/pptx/pptx_emf.dart';

Uint8List _record(int type, int length, void Function(ByteData) fill) {
  final data = ByteData(length)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, length, Endian.little);
  fill(data);
  return data.buffer.asUint8List();
}

Uint8List _textEmf(String text, {List<int>? advances}) {
  final textBytes = Uint8List(text.length * 2);
  final textData = ByteData.sublistView(textBytes);
  for (var i = 0; i < text.length; i++) {
    textData.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
  }
  final advanceOffset = 76 + ((textBytes.length + 3) ~/ 4) * 4;
  final textLength = advanceOffset + (advances?.length ?? 0) * 4;
  final records = <Uint8List>[
    _record(1, 88, (data) {
      data
        ..setInt32(8, 0, Endian.little)
        ..setInt32(12, 0, Endian.little)
        ..setInt32(16, 1280, Endian.little)
        ..setInt32(20, 360, Endian.little)
        ..setUint32(40, 0x464D4520, Endian.little);
    }),
    _record(9, 16, (data) {
      data
        ..setInt32(8, 1280, Endian.little)
        ..setInt32(12, 360, Endian.little);
    }),
    _record(24, 12, (data) {
      data.setUint32(8, 0x001E3CC8, Endian.little);
    }),
    _record(82, 104, (data) {
      data
        ..setUint32(8, 1, Endian.little)
        ..setInt32(12, -64, Endian.little)
        ..setInt32(28, 700, Endian.little);
    }),
    _record(37, 12, (data) {
      data.setUint32(8, 1, Endian.little);
    }),
    _record(84, textLength, (data) {
      data
        ..setInt32(36, 100, Endian.little)
        ..setInt32(40, 160, Endian.little)
        ..setUint32(44, text.length, Endian.little)
        ..setUint32(48, 76, Endian.little)
        ..setUint32(72, advances == null ? 0 : advanceOffset, Endian.little);
      data.buffer.asUint8List().setRange(76, 76 + textBytes.length, textBytes);
      for (var i = 0; i < (advances?.length ?? 0); i++) {
        data.setInt32(advanceOffset + i * 4, advances![i], Endian.little);
      }
    }),
    _record(14, 8, (_) {}),
  ];
  return Uint8List.fromList(records.expand((record) => record).toList());
}

void main() {
  test('zet een tekstgerichte PowerPoint-EMF om naar een zichtbare PNG', () {
    final png = rasterizeTextEmf(_textEmf('Marktconsultatie'));

    expect(png, isNotNull);
    final decoded = img.decodePng(png!);
    expect(decoded, isNotNull);
    expect([decoded!.width, decoded.height], [1280, 360]);
    expect(decoded.any((pixel) => pixel.a > 0), isTrue);
  });

  test('weigert onbekende tekenrecords in plaats van stil beeld te missen', () {
    final bytes = _textEmf('Tekst').toList();
    final unknown = _record(4, 8, (_) {});
    bytes.insertAll(bytes.length - 8, unknown);

    expect(rasterizeTextEmf(Uint8List.fromList(bytes)), isNull);
  });

  test('respecteert de door PowerPoint opgeslagen letterposities', () {
    final png = rasterizeTextEmf(_textEmf('AA', advances: [400, 20]));
    final decoded = img.decodePng(png!)!;
    final range = decoded.getRange(480, 80, 90, 120);
    var visible = false;
    while (range.moveNext()) {
      if (range.current.a > 0) visible = true;
    }

    expect(
      visible,
      isTrue,
      reason: 'de tweede A hoort rond x=500 te staan, niet direct na de eerste',
    );
  });
}
