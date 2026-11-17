import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/media/timed_captions.dart';

void main() {
  test('VTT headers, comments and styles never become transcript text', () {
    final result = parseTimedCaptions('''WEBVTT
Kind: captions
Language: en

NOTE This is not speech
00:00:00.000 --> 00:00:01.000
Not speech either

STYLE
::cue { color: lime; }

arbitrary-cue-id
00:00:10.349 --> 00:00:12.500 align:start position:0%
<v Reader><b>Hello</b> &amp; <00:00:11.000>welcome.</v>
Second line.
''');
    expect(result, hasLength(1));
    expect(result.single.text, 'Hello & welcome. Second line.');
    expect(result.single.start, const Duration(milliseconds: 10349));
    expect(result.single.end, const Duration(milliseconds: 12500));
  });

  test('rolling dedup only removes overlapping suffix-prefix repetition', () {
    const input = '''WEBVTT

00:00:01.000 --> 00:00:03.000
One two

00:00:02.000 --> 00:00:04.000
two three

00:00:03.000 --> 00:00:05.000
two three four

00:00:06.000 --> 00:00:07.000
four
''';
    final result = parseTimedCaptions(input, rolling: true);
    expect(result.map((c) => c.text), ['One two', 'three', 'four', 'four']);
    expect(result[2].start, const Duration(seconds: 3));
    expect(parseTimedCaptions(input)[1].text, 'two three');
  });

  test('SRT preserves end times, while malformed timing fails explicitly', () {
    final result = parseTimedCaptions('''1
00:01:02,100 --> 00:01:03,200
Text
''');
    expect(result.single.end, const Duration(milliseconds: 63200));
    for (final value in [
      '00:01:90.000 --> 00:01:91.000\nBad',
      '00:01:02.000 --> 00:01:01.000\nBackwards',
      '#EXTM3U\n#EXT-X-VERSION:3',
      '<html>Not captions</html>',
    ]) {
      expect(
        () => parseTimedCaptions(value),
        throwsA(isA<CaptionParseException>()),
      );
    }
  });

  test('contiguous automatic display cues remove repeated carried lines', () {
    const input = '''WEBVTT

00:00:01.000 --> 00:00:02.000
Our<00:00:01.500><c> example</c>

00:00:02.000 --> 00:00:02.010
Our example

00:00:02.010 --> 00:00:03.000
Our example
continues<00:00:02.500><c> here</c>

00:00:04.000 --> 00:00:05.000
here
''';
    final result = parseTimedCaptions(input, rolling: true);
    expect(result.map((cue) => cue.text), [
      'Our example',
      'continues here',
      'here',
    ]);
    expect(result[1].start, const Duration(milliseconds: 2010));
    expect(parseTimedCaptions(input), hasLength(4));
  });
}
