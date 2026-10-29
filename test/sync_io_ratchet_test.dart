import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de sync-IO-poort (`syncIoCallsIn` in
/// `tool/check_conventions.dart`).
///
/// De poort bewaakt `lib/widgets/` en `lib/state/` op `*Sync`-aanroepen van
/// `dart:io`: die blokkeren de enige isolate die beelden mag tekenen. Zo stond
/// er een `resolveSymbolicLinksSync` per build in de beeldpijplijn (#2624) en
/// een `existsSync` per toetsaanslag in de naamvalidator van de
/// aanmaakdialoog (#2636) — beide ontdekt door meten, niet door de poort.
///
/// Het instrument is een regelscan; deze tests dekt de vormen af die er in de
/// codebase voorkomen of verleidelijk zijn: de aangeroepen methode op een
/// `File`, een commentaarregel die de naam vermeldt, en de async-tweeling die
/// níét mag vallen.
void main() {
  Map<String, List<int>> meet(String source) =>
      syncIoCallsIn({'lib/widgets/x.dart': source});

  group('de vormen van de codebase', () {
    test('een sync-aanroep op een receiver valt', () {
      final hits = meet('''
void f() {
  if (File(path).existsSync()) {}
  final bytes = File(path).readAsBytesSync();
  dir.listSync();
  link.resolveSymbolicLinksSync();
}
''');
      expect(hits['lib/widgets/x.dart'], hasLength(4));
    });

    test('een aanroep in een expressie of geneste call valt óók', () {
      final hits = meet('''
void f() {
  use(File(path).readAsStringSync().trim());
}
''');
      expect(hits['lib/widgets/x.dart'], hasLength(1));
    });

    test('de async-tweeling is geen treffer', () {
      final hits = meet('''
void f() async {
  await File(path).exists();
  await File(path).readAsBytes();
  await dir.list().toList();
  await file.stat();
}
''');
      expect(hits, isEmpty);
    });

    test('eigen sync-helpers zijn geen dart:io-treffer', () {
      // writeBytesAtomicSyncRetrying is een eigen helper in
      // lib/utils/atomic_file.dart — bewust synchroon, met de afweging in
      // zijn dartdoc. De poort hoort alleen dart:io-methoden te zien.
      final hits = meet('''
void f() {
  writeBytesAtomicSyncRetrying(File(path), bytes);
  writeBytesAtomicSync(File(path), bytes);
}
''');
      expect(hits, isEmpty);
    });
  });

  group('de blinde vlekken', () {
    test('een commentaarregel die de methode noemt is geen aanroep', () {
      final hits = meet('''
// Gebruik geen File(path).existsSync() hier — dat blokkeert de isolate.
// Ook existsSync los in tekst mag niet tellen.
void f() {}
''');
      expect(hits, isEmpty);
    });
  });
}
