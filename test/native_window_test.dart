import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/native_window_io.dart';

/// De vensterinstelling bij het opstarten (`main.dart` roept dit als eerste aan
/// op desktop). Het is gewone `dart:io`-code met een platformcheck, geen
/// web-helft — dus toetsbaar, mits je het `window_manager`-kanaal namaakt.
///
/// Wat hier écht op het spel staat is de MINIMUMGROOTTE. OciDeck's shell is een
/// drieluik (diastrook, editor, preview); onder ongeveer 1000x650 vouwen die
/// panelen over elkaar heen. Zonder deze aanroep kan de gebruiker het venster
/// kleiner slepen dan de app aankan, en dat is precies het soort ding dat
/// niemand merkt tot het bij iemand anders op het scherm staat.
void main() {
  const channel = MethodChannel('window_manager');

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          // Deze drie geven een bool terug en worden meteen ontleed door
          // window_manager; null zou daar op een cast klappen.
          switch (call.method) {
            case 'isFullScreen':
            case 'isMaximized':
            case 'isMinimized':
              return false;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MethodCall callTo(String method) =>
      calls.firstWhere((c) => c.method == method);

  bool hasCall(String method) => calls.any((c) => c.method == method);

  testWidgets('stelt het venster in op een desktopplatform', (tester) async {
    // Deze suite draait op de Dart-VM, dus altijd op een desktop-OS. Zou dat
    // ooit veranderen, dan is de bewering hieronder niet meer waar en hoort de
    // test dat te zeggen in plaats van stilletjes leeg te draaien.
    expect(
      Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      isTrue,
      reason: 'de testrunner draait op desktop; anders klopt deze test niet',
    );

    await configureNativeWindow();

    expect(hasCall('ensureInitialized'), isTrue);
    expect(hasCall('waitUntilReadyToShow'), isTrue);

    // De ondergrens van de drieluik-shell. Een vaste maat, bewust getoetst:
    // hem per ongeluk laten vallen is onzichtbaar tot het venster te klein is.
    final minimum = callTo('setMinimumSize');
    expect(minimum.arguments['width'], minimumWindowSize.width);
    expect(minimum.arguments['height'], minimumWindowSize.height);
    expect(minimumWindowSize, const Size(1000, 650));

    expect(callTo('setTitle').arguments['title'], 'OciDeck');

    // Tonen én focussen: zonder focus start de app achter andere vensters.
    expect(hasCall('show'), isTrue);
    expect(hasCall('focus'), isTrue);

    // Sluiten wordt onderschept, zodat OciDeck bij niet-opgeslagen werk kan
    // vragen wat er moet gebeuren in plaats van het weg te gooien.
    expect(callTo('setPreventClose').arguments['isPreventClose'], isTrue);
  });

  testWidgets('tonen gebeurt pas nadat het venster klaar is', (tester) async {
    await configureNativeWindow();

    final ready = calls.indexWhere((c) => c.method == 'waitUntilReadyToShow');
    final shown = calls.indexWhere((c) => c.method == 'show');
    final prevent = calls.indexWhere((c) => c.method == 'setPreventClose');
    expect(ready, isNonNegative);
    expect(
      shown,
      greaterThan(ready),
      reason: 'tonen vóór het venster klaar is geeft een flikkering',
    );
    // En het geheel is áf voor `configureNativeWindow` terugkeert. Stond dit in
    // de `VoidCallback` van waitUntilReadyToShow, dan werd de `async` body wel
    // gestart maar niet afgewacht en was deze aanroep hier nog niet gedaan.
    expect(prevent, isNonNegative);
  });
}
