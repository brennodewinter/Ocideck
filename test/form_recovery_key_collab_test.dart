// The editorial recovery key and the collaboration recovery key are two different things that
// look alike (FORM_INTAKE.md §5.9). Pasting one into the other's "restore" must be refused —
// by both sides — before anything is installed.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_recovery_key.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

void main() {
  final seed = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final other = Uint8List.fromList(List.generate(32, (i) => 200 - i));

  test('a collaboration recovery key is not an editorial one', () {
    final collab = encodeRecoveryKey(seed, other);
    final r = decodeFormRecoveryKey(collab);
    expect(r, isA<FormRecoveryRefused>());
    expect((r as FormRecoveryRefused).issue, FormRecoveryIssue.format);
  });

  test('an editorial recovery key is not a collaboration one', () {
    final editorial = encodeFormRecoveryKey(
      signingSeed: seed,
      ageIdentity: generateAgeIdentity(),
    );
    expect(
      () => decodeRecoveryKey(editorial),
      throwsA(
        isA<RecoveryKeyException>().having(
          (e) => e.reason,
          'reason',
          RecoveryKeyError.format,
        ),
      ),
    );
  });

  test('both are still read by their own side', () {
    expect(decodeRecoveryKey(encodeRecoveryKey(seed, other)).ed25519Seed, seed);
    final identity = generateAgeIdentity();
    final r = decodeFormRecoveryKey(
      encodeFormRecoveryKey(signingSeed: seed, ageIdentity: identity),
    );
    expect((r as FormRecoveredKey).ageIdentity, identity);
  });
}
