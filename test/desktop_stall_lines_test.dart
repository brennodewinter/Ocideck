import 'package:flutter_test/flutter_test.dart';

import '../test_driver/desktop_smoke_process.dart';

void main() {
  test(
    'desktop journey recognises a real stall warning and its work label',
    () {
      const stall =
          '12:00:00 WARN UI-isolate 1002 ms onbereikbaar — werk: export';
      const unlabelled = '12:00:01 WARN UI-isolate 936 ms onbereikbaar';
      expect(
        desktopStallLines([
          '12:00:00 INFO sessie: OciDeck',
          '12:00:00 INFO sample: UI-isolate 1 ms onbereikbaar',
          stall,
          unlabelled,
        ]),
        [stall, unlabelled],
      );
    },
  );
}
