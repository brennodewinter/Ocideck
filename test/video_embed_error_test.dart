import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

const _l10n = AppLocalizations(Locale('nl'));

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('videoEmbedErrorFromCode', () {
    test('101/150 = de eigenaar zet insluiten uit (de vaakste oorzaak)', () {
      expect(videoEmbedErrorFromCode('101'), VideoEmbedError.embeddingDisabled);
      expect(videoEmbedErrorFromCode('150'), VideoEmbedError.embeddingDisabled);
    });

    test('100 en Vimeo-fouten = niet beschikbaar', () {
      expect(videoEmbedErrorFromCode('100'), VideoEmbedError.unavailable);
      expect(
        videoEmbedErrorFromCode('PrivacyError'),
        VideoEmbedError.unavailable,
      );
      expect(
        videoEmbedErrorFromCode('NotFoundError'),
        VideoEmbedError.unavailable,
      );
    });

    test('2/5 = ongeldige link', () {
      expect(videoEmbedErrorFromCode('2'), VideoEmbedError.invalid);
      expect(videoEmbedErrorFromCode('5'), VideoEmbedError.invalid);
    });

    test('noapi en onbekende codes vallen naar netwerk', () {
      expect(videoEmbedErrorFromCode('noapi'), VideoEmbedError.network);
      expect(videoEmbedErrorFromCode('iets-nieuws'), VideoEmbedError.network);
      expect(videoEmbedErrorFromCode(''), VideoEmbedError.network);
    });
  });

  group('elke fout heeft een eigen zichtbare reden', () {
    test('titel, detail en icoon zijn per foutsoort uniek', () {
      // Zouden twee oorzaken dezelfde tekst of hetzelfde icoon delen, dan is de
      // "waarom laadt dit niet"-vraag die de gebruiker stelde nog steeds niet
      // beantwoord.
      final titles = <String>{};
      final details = <String>{};
      final icons = <IconData>{};
      for (final error in VideoEmbedError.values) {
        final c = videoEmbedErrorContent(_l10n, error);
        expect(c.title.trim(), isNotEmpty);
        expect(c.detail.trim(), isNotEmpty);
        expect(titles.add(c.title), isTrue, reason: 'titel dubbel: $error');
        expect(details.add(c.detail), isTrue, reason: 'detail dubbel: $error');
        expect(icons.add(c.icon), isTrue, reason: 'icoon dubbel: $error');
      }
      expect(titles, hasLength(VideoEmbedError.values.length));
    });

    test('insluiten-uit noemt de bron als alternatief', () {
      // De vaakste oorzaak verdient de meest bruikbare tekst: níet "stuk", maar
      // "kijk op de bron zelf".
      final c = videoEmbedErrorContent(
        _l10n,
        VideoEmbedError.embeddingDisabled,
      );
      expect(c.detail.toLowerCase(), contains('bron'));
    });
  });
}
