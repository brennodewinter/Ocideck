// The frozen editor card (FORM_INTAKE.md §5.1, D5): `test/fixtures/form_editor_card_vector.json`
// is what version 1 produces, and what a second implementation checks itself against. Kept apart
// from `form_editor_card_test.dart` because it reads a file (`dart:io`).

import 'dart:convert';
import 'dart:io';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

void main() {
  final vector =
      jsonDecode(
            File(
              'test/fixtures/form_editor_card_vector.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('the file says what the code produces', () {
    final card = createFormEditorCard(
      name: vector['name']! as String,
      age: vector['age']! as String,
      signPublicKey: base32Decode(vector['sign']! as String)!,
    );
    expect(card.kid, vector['kid']);
    expect(card.toText(), vector['text']);
    expect(card.fingerprint, vector['fingerprint']);
  });

  test('and the code reads the file back to the same card', () {
    final result = parseFormEditorCard(vector['text']! as String);
    expect(
      (result as FormEditorCardParsed).card.fingerprint,
      vector['fingerprint'],
    );
  });
}
