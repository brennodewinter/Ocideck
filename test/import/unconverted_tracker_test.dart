import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';
import 'package:ocideck/services/import/pipeline/unconverted_tracker.dart';

void main() {
  test(
    'builds a note body listing every issue under a slide-numbered heading',
    () {
      final body = UnconvertedTracker.buildNoteBody(3, [
        const ConversionIssue(
          slideIndex: 2,
          feature: 'SmartArt "Organigram"',
          description: 'niet ondersteund',
        ),
        const ConversionIssue(
          slideIndex: 2,
          feature: 'Audio "intro.mp3"',
          description: 'niet overgenomen',
        ),
      ]);

      expect(body, contains('# Niet overgenomen van slide 3'));
      expect(body, contains('- SmartArt "Organigram": niet ondersteund'));
      expect(body, contains('- Audio "intro.mp3": niet overgenomen'));
    },
  );

  test('annotates partially salvaged issues', () {
    final body = UnconvertedTracker.buildNoteBody(5, [
      const ConversionIssue(
        slideIndex: 4,
        feature: 'SmartArt',
        description: 'visueel niet overgenomen',
        salvagedAs: 'tekst als bullets',
      ),
    ]);

    expect(body, contains('(deels overgenomen: tekst als bullets)'));
  });

  test('hasLoss is true when there are issues', () {
    expect(
      UnconvertedTracker.hasLoss([
        const ConversionIssue(slideIndex: 0, feature: 'x', description: 'y'),
      ]),
      isTrue,
    );
    expect(UnconvertedTracker.hasLoss(const []), isFalse);
  });

  test('buildDeckNoteBody uses a document-level heading', () {
    final body = UnconvertedTracker.buildDeckNoteBody([
      const ConversionIssue(
        slideIndex: -1,
        feature: 'Keynote IWA-intern',
        description: 'niet overgenomen (pas in een volgende milestone)',
        salvagedAs: 'voorbeeldafbeelding',
      ),
    ]);
    expect(body, contains('# Niet overgenomen van dit document'));
    expect(body, contains('- Keynote IWA-intern: niet overgenomen'));
    expect(body, contains('(deels overgenomen: voorbeeldafbeelding)'));
  });
}
