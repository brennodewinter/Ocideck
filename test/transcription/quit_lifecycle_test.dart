// #2631: elke best-effort-afsluitstap is begrensd en foutdovend — een stap
// die gooit of blijft hangen mag quitApp nooit bereiken blokkeren.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/shell/quit_lifecycle.dart';

void main() {
  test('een gooiende stap stopt de keten niet', () async {
    var threw = false;
    await boundedQuitStep(
      () async => throw StateError('kapot'),
      label: 'proef',
      budget: const Duration(seconds: 1),
    ).whenComplete(() => threw = true);
    expect(threw, isTrue);
  });

  test('een hangende stap valt terug op het budget', () {
    fakeAsync((async) {
      var done = false;
      unawaited(
        boundedQuitStep(
          () => Future<void>.delayed(const Duration(minutes: 10)),
          label: 'proef',
          budget: const Duration(seconds: 3),
        ).whenComplete(() => done = true),
      );
      async.elapse(const Duration(seconds: 3));
      async.flushTimers();
      expect(done, isTrue);
    });
  });
}
