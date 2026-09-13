import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Zet een tekstgerichte Enhanced Metafile om naar een begrensde PNG.
///
/// PowerPoint gebruikt EMF geregeld voor geplakte tekst- en procesblokken.
/// Flutter kan die bytes niet tonen. Deze lezer ondersteunt bewust alleen de
/// veilige, tekstgerichte recordset die OciDeck zelf kan reconstrueren. Een
/// EMF met paden, bitmaps of onbekende records geeft `null`, zodat de bestaande
/// parsegrens het verlies zichtbaar meldt in plaats van een onvolledig beeld te
/// verzinnen.
Uint8List? rasterizeTextEmf(Uint8List bytes) {
  final parsed = _parseTextEmf(bytes);
  if (parsed == null || parsed.runs.isEmpty) return null;
  final size = _rasterSize(parsed.width, parsed.height);
  if (size == null) return null;
  final scale = size.width / parsed.width;
  final canvas = img.Image(
    width: size.width,
    height: size.height,
    numChannels: 4,
  )..clear(img.ColorRgba8(255, 255, 255, 0));

  for (final run in parsed.runs) {
    final fontHeight = (run.fontHeight.abs() * scale).round().clamp(8, 96);
    final font = fontHeight >= 34
        ? img.arial48
        : (fontHeight >= 19 ? img.arial24 : img.arial14);
    final x = (run.x * scale).round();
    final baseline = (run.y * scale).round();
    final y = baseline - (font.lineHeight * 0.82).round();
    final color = img.ColorRgba8(run.red, run.green, run.blue, 255);
    if (_isBullet(run.text)) {
      _drawBullet(canvas, x, baseline, fontHeight, color);
      continue;
    }
    if (run.advances == null) {
      _drawText(canvas, run.text, font, x, y, color, bold: run.bold);
      continue;
    }
    var cursor = x;
    for (var i = 0; i < run.text.length; i++) {
      final character = run.text[i];
      if (_isBullet(character)) {
        _drawBullet(canvas, cursor, baseline, fontHeight, color);
      } else {
        _drawText(canvas, character, font, cursor, y, color, bold: run.bold);
      }
      cursor += (run.advances![i] * scale).round();
    }
  }
  return Uint8List.fromList(img.encodePng(canvas));
}

bool _isBullet(String text) =>
    const {'\uf0b7', '\u2022', '\u25cf', '\u00b7'}.contains(text);

void _drawBullet(
  img.Image canvas,
  int x,
  int baseline,
  int fontHeight,
  img.Color color,
) => img.fillCircle(
  canvas,
  x: x + (fontHeight * 0.18).round(),
  y: baseline - (fontHeight * 0.28).round(),
  radius: (fontHeight * 0.09).round().clamp(1, 8),
  color: color,
);

void _drawText(
  img.Image canvas,
  String text,
  img.BitmapFont font,
  int x,
  int y,
  img.Color color, {
  required bool bold,
}) {
  img.drawString(canvas, text, font: font, x: x, y: y, color: color);
  if (bold) {
    img.drawString(canvas, text, font: font, x: x + 1, y: y, color: color);
  }
}

({int width, int height})? _rasterSize(int width, int height) {
  if (width <= 0 || height <= 0) return null;
  final scale = (1920 / width).clamp(0.1, 1.0);
  final scaledHeight = height * scale;
  final boundedScale = scaledHeight > 1080 ? 1080 / height : scale;
  return (
    width: (width * boundedScale).round().clamp(1, 1920),
    height: (height * boundedScale).round().clamp(1, 1080),
  );
}

_ParsedEmf? _parseTextEmf(Uint8List bytes) {
  if (bytes.length < 88) return null;
  final data = ByteData.sublistView(bytes);
  if (_u32(data, 0) != 1 || _u32(data, 40) != 0x464D4520) return null;
  var width = (_i32(data, 16) - _i32(data, 8)).abs();
  var height = (_i32(data, 20) - _i32(data, 12)).abs();
  var offset = 0;
  var records = 0;
  var state = const _EmfState();
  final stack = <_EmfState>[];
  final fonts = <int, _EmfFont>{};
  final runs = <_EmfTextRun>[];

  while (offset + 8 <= bytes.length && records++ < 10000) {
    final type = _u32(data, offset);
    final length = _u32(data, offset + 4);
    if (length < 8 || offset + length > bytes.length) return null;
    switch (type) {
      case 9: // EMR_SETWINDOWEXTEX
        if (length < 16) return null;
        width = _i32(data, offset + 8).abs();
        height = _i32(data, offset + 12).abs();
      case 18: // EMR_SETBKMODE
      case 22: // EMR_SETTEXTALIGN
      case 30: // EMR_INTERSECTCLIPRECT
      case 40: // EMR_DELETEOBJECT
      case 70: // EMR_GDICOMMENT
        break;
      case 24: // EMR_SETTEXTCOLOR
        if (length < 12) return null;
        final color = _u32(data, offset + 8);
        state = state.copyWith(
          red: color & 0xFF,
          green: (color >> 8) & 0xFF,
          blue: (color >> 16) & 0xFF,
        );
      case 33: // EMR_SAVEDC
        stack.add(state);
      case 34: // EMR_RESTOREDC
        if (stack.isNotEmpty) state = stack.removeLast();
      case 37: // EMR_SELECTOBJECT
        if (length < 12) return null;
        final handle = _u32(data, offset + 8);
        state = state.copyWith(font: fonts[handle] ?? state.font);
      case 82: // EMR_EXTCREATEFONTINDIRECTW
        if (length < 104) return null;
        final handle = _u32(data, offset + 8);
        fonts[handle] = _EmfFont(
          height: _i32(data, offset + 12),
          bold: _i32(data, offset + 28) >= 600,
        );
      case 84: // EMR_EXTTEXTOUTW
        final run = _readTextRun(data, bytes, offset, length, state);
        if (run == null) return null;
        if (run.text.trim().isNotEmpty || run.text == '\uf0b7') runs.add(run);
      case 1: // EMR_HEADER
      case 10: // EMR_SETWINDOWORGEX
      case 14: // EMR_EOF
        break;
      default:
        return null;
    }
    offset += length;
    if (type == 14) break;
  }
  if (records >= 10000 || width <= 0 || height <= 0) return null;
  return _ParsedEmf(width: width, height: height, runs: runs);
}

_EmfTextRun? _readTextRun(
  ByteData data,
  Uint8List bytes,
  int recordOffset,
  int recordLength,
  _EmfState state,
) {
  if (recordLength < 76) return null;
  final count = _u32(data, recordOffset + 44);
  final stringOffset = _u32(data, recordOffset + 48);
  if (count > 100000 || stringOffset > recordLength) return null;
  final start = recordOffset + stringOffset;
  final end = start + count * 2;
  if (end > recordOffset + recordLength || end > bytes.length) return null;
  final text = String.fromCharCodes([
    for (var i = start; i < end; i += 2) _u16(data, i),
  ]);
  final options = _u32(data, recordOffset + 52);
  final advanceOffset = _u32(data, recordOffset + 72);
  final advances = _readAdvances(
    data,
    recordOffset,
    recordLength,
    count,
    advanceOffset,
    paired: options & 0x2000 != 0,
  );
  if (advanceOffset != 0 && advances == null) return null;
  return _EmfTextRun(
    x: _i32(data, recordOffset + 36),
    y: _i32(data, recordOffset + 40),
    text: text,
    fontHeight: state.font.height,
    bold: state.font.bold,
    red: state.red,
    green: state.green,
    blue: state.blue,
    advances: advances,
  );
}

List<int>? _readAdvances(
  ByteData data,
  int recordOffset,
  int recordLength,
  int count,
  int relativeOffset, {
  required bool paired,
}) {
  if (relativeOffset == 0 || count == 0) return null;
  final values = count * (paired ? 2 : 1);
  final start = recordOffset + relativeOffset;
  final end = start + values * 4;
  if (relativeOffset > recordLength || end > recordOffset + recordLength) {
    return null;
  }
  return [
    for (var i = 0; i < count; i++) _i32(data, start + i * (paired ? 8 : 4)),
  ];
}

int _u16(ByteData data, int offset) => data.getUint16(offset, Endian.little);
int _u32(ByteData data, int offset) => data.getUint32(offset, Endian.little);
int _i32(ByteData data, int offset) => data.getInt32(offset, Endian.little);

class _ParsedEmf {
  const _ParsedEmf({
    required this.width,
    required this.height,
    required this.runs,
  });
  final int width;
  final int height;
  final List<_EmfTextRun> runs;
}

class _EmfFont {
  const _EmfFont({this.height = -48, this.bold = false});
  final int height;
  final bool bold;
}

class _EmfState {
  const _EmfState({
    this.font = const _EmfFont(),
    this.red = 0,
    this.green = 0,
    this.blue = 0,
  });
  final _EmfFont font;
  final int red;
  final int green;
  final int blue;

  _EmfState copyWith({_EmfFont? font, int? red, int? green, int? blue}) =>
      _EmfState(
        font: font ?? this.font,
        red: red ?? this.red,
        green: green ?? this.green,
        blue: blue ?? this.blue,
      );
}

class _EmfTextRun {
  const _EmfTextRun({
    required this.x,
    required this.y,
    required this.text,
    required this.fontHeight,
    required this.bold,
    required this.red,
    required this.green,
    required this.blue,
    required this.advances,
  });
  final int x;
  final int y;
  final String text;
  final int fontHeight;
  final bool bold;
  final int red;
  final int green;
  final int blue;
  final List<int>? advances;
}
