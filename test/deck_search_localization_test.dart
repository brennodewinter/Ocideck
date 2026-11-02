import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/deck_search_localization.dart';
import 'package:ocideck/utils/deck_text_search.dart';
import 'package:ocideck/utils/text_search.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('en'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  String location(String field, String label) => deckSearchLocation(
    const AppLocalizations(Locale('en')),
    DeckTextMatch(
      slideId: 'slide',
      slideIndex: 0,
      fieldId: field,
      fieldLabel: label,
      text: 'same',
      range: const TextMatchRange(0, 4),
      context: 'same',
    ),
  );

  test('same text in different cells has a translated row and column', () {
    expect(location('tableRows.2.1', 'Tabel'), 'Table · Row 3 · Column 2');
    expect(location('tableRows.2.2', 'Tabel'), 'Table · Row 3 · Column 3');
    expect(location('tableRows.x.2', 'Tabel'), 'Table');
  });

  test(
    'column headings, captions and repeated fields have distinct locations',
    () {
      expect(location('columnTitle1', 'Kop'), 'Heading · Left');
      expect(location('columnTitle2', 'Kop'), 'Heading · Right');
      expect(location('imageCaption2', 'Bijschrift'), 'Caption · Right');
      expect(location('bullets2.3', 'Bullets rechts'), 'Bullets right · 4');
      expect(location('timeline.1.title', 'Tijdlijn'), 'Timeline · 2');
      expect(location('title', 'Titel'), 'Title');
    },
  );
}
