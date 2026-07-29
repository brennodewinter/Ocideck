import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/draft_store.dart';

/// `draft_store.dart` definieert twee uitzonderingen die elders in de testbomen
/// alleen als type worden gecontroleerd (`throwsA(isA<…>)`). Hun `toString` —
/// de tekst die in een foutmelding of logregel terechtkomt — had daarom geen
/// dekking.
void main() {
  test('DraftStoreUnsupported.toString bevat de boodschap', () {
    const e = DraftStoreUnsupported('te groot voor het klembord');
    expect(e.toString(), contains('te groot voor het klembord'));
    expect(e.toString(), contains('DraftStoreUnsupported'));
  });

  test('DraftStoreCorrupt.toString benoemt de map en de oorzaak', () {
    const e = DraftStoreCorrupt('decks/alpha', 'kapotte sleutel');
    expect(e.toString(), contains('decks/alpha'));
    expect(e.toString(), contains('kapotte sleutel'));
    expect(e.toString(), contains('DraftStoreCorrupt'));
  });
}
