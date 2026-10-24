// Tests for uniqueMeetingNick (#2533): throwaway per-join nicks — the MUC-
// safe shape and no reuse across joins (a stable nick would make a
// participant linkable across rooms).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_nick.dart';

void main() {
  test('has the muc_resource_validate-safe shape (geen streepje!)', () {
    final nick = uniqueMeetingNick(Random(7));
    expect(nick, matches(RegExp(r'^ocideck_[0-9a-f]{8}$')));
  });

  test('successive joins get different nicks', () {
    final nicks = {for (var i = 0; i < 50; i++) uniqueMeetingNick()};
    expect(nicks.length, 50);
  });

  test('a seeded random is deterministic for tests', () {
    expect(uniqueMeetingNick(Random(1)), uniqueMeetingNick(Random(1)));
  });
}
