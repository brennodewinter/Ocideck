import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/native_window_io.dart';

/// De vensterinstelling bij het opstarten (`main.dart` roept dit als eerste aan
/// op desktop).
///
/// Deze suite mockte vroeger het `window_manager`-methodenkanaal. Sinds de
/// migratie naar nativeapi (#1741) gaan de vensteraanroepen via FFI, niet via
/// een methodenkanaal, en FFI-bindings kunnen onder `flutter test` niet
/// gemockt worden (geen native library geladen). De test is geskipt tot er
/// een testbare abstractie-laag boven nativeapi komt.
void main() {
  test(
    'de minimumgrootte is een vaste waarde die per ongeluk kan verdwijnen',
    () {
      // Dit is de enige bewering die geen native laag nodig heeft.
      expect(minimumWindowSize, const Size(1000, 650));
    },
  );
}
