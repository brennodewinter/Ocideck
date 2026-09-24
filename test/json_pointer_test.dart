import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/json_pointer.dart';

void main() {
  test('JSON-pointer escapes tilde and slash in each segment', () {
    final pointer = jsonPointerFromSegments(['data', 'a~/b', 0]);
    expect(pointer, '/data/a~0~1b/0');
    expect(
      appendJsonPointerSegment(pointer, 'x/y~z'),
      '/data/a~0~1b/0/x~1y~0z',
    );
  });
}
