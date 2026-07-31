// Tests for the invite-link helper (`lib/collab/matrix_invite.dart`, P-D UX).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_invite.dart';

void main() {
  test('builds a matrix.to link that round-trips back to the room id', () {
    final link = buildMatrixInvite('!abc:hs.example');
    expect(link, startsWith('https://matrix.to/#/'));
    expect(parseMatrixInvite(link), '!abc:hs.example');
  });

  test('accepts an alias and a bare id/alias', () {
    expect(
      parseMatrixInvite(buildMatrixInvite('#room:hs.example')),
      '#room:hs.example',
    );
    expect(parseMatrixInvite('!abc:hs.example'), '!abc:hs.example');
    expect(parseMatrixInvite('#room:hs.example'), '#room:hs.example');
  });

  test('reads a link whose id was percent-encoded (# → %23)', () {
    expect(
      parseMatrixInvite('https://matrix.to/#/%23room:hs.example'),
      '#room:hs.example',
    );
  });

  test('takes only the first fragment segment (ignores via/event parts)', () {
    expect(
      parseMatrixInvite('https://matrix.to/#/!abc:hs.example/\$event:hs'),
      '!abc:hs.example',
    );
  });

  test('rejects anything that is not a room id or alias', () {
    expect(parseMatrixInvite(''), isNull);
    expect(parseMatrixInvite('https://example.com/#/!abc:hs'), isNull);
    expect(parseMatrixInvite('https://matrix.to/#/@user:hs'), isNull);
    expect(parseMatrixInvite('just text'), isNull);
    expect(parseMatrixInvite('!:'), isNull);
  });
}
