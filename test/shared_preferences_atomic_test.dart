import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/shared_preferences_atomic_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck-prefs');
    file = File(p.join(dir.path, 'shared_preferences.json'));
    addTearDown(() => dir.delete(recursive: true));
    addTearDown(() => AtomicFilePreferencesStore.onCorruption = null);
  });

  // #2628: een afgebroken schrijfbeurt (crash, stroomstoring, geforceerd
  // afsluiten) mocht elke volgende start breken: het JSON-bestand was half
  // en getInstance() gooide voor altijd een FormatException.
  test('corrupt bestand gaat in quarantaine en de app start leeg', () async {
    await file.writeAsString('{"flutter.a": 1, "flutter.b": "kap');
    String? quarantined;
    AtomicFilePreferencesStore.onCorruption = (path) => quarantined = path;

    final store = AtomicFilePreferencesStore(file: file);
    expect(await store.getAll(), isEmpty);

    // Het corrupte bestand ligt niet meer op zijn plek, maar is ook niet
    // weggegooid: een kopie voor wie er iets uit wil terughalen.
    expect(await file.exists(), isFalse);
    expect(quarantined, isNotNull);
    expect(await File(quarantined!).exists(), isTrue);

    // En daarna werkt opslaan weer gewoon — de vorige store had dat voorgoed
    // verbroken gemaakt.
    expect(await store.setValue('String', 'flutter.k', 'waarde'), isTrue);
    final written = jsonDecode(await file.readAsString()) as Map;
    expect(written['flutter.k'], 'waarde');

    // Een volgende instantie leest die verse inhoud weer terug.
    final next = AtomicFilePreferencesStore(file: file);
    expect(await next.getAll(), containsPair('flutter.k', 'waarde'));
  });

  test('gezond bestand leest zijn eigen sleutels (flutter-prefix)', () async {
    await file.writeAsString(
      jsonEncode({'flutter.a': 1, 'flutter.b': 'x', 'other.c': true}),
    );
    final store = AtomicFilePreferencesStore(file: file);
    final all = await store.getAll();
    expect(all, containsPair('flutter.a', 1));
    expect(all, containsPair('flutter.b', 'x'));
    // De plugin filtert op dezelfde `flutter.`-prefix.
    expect(all, isNot(contains('other.c')));
  });

  test('setValue schrijft de hele map atomair (geen prefix aan de sleutel)',
      () async {
    final store = AtomicFilePreferencesStore(file: file);
    expect(await store.setValue('int', 'flutter.n', 7), isTrue);
    expect(await store.setValue('bool', 'flutter.b', false), isTrue);
    final written = jsonDecode(await file.readAsString()) as Map;
    expect(written['flutter.n'], 7);
    expect(written['flutter.b'], false);
  });

  test('remove en clear schrappen alleen flutter-sleutels', () async {
    await file.writeAsString(
      jsonEncode({'flutter.a': 1, 'other.keep': 2}),
    );
    final store = AtomicFilePreferencesStore(file: file);
    await store.remove('flutter.a');
    expect(await store.getAll(), isEmpty);
    final written = jsonDecode(await file.readAsString()) as Map;
    // De cache bewaart de hele map — de niet-flutter-sleutel blijft staan,
    // zoals de plugin het ook deed (hij schreef de volledige cache).
    expect(written, isNot(contains('flutter.a')));
    expect(written['other.keep'], 2);
  });
}
