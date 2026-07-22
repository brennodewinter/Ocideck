// Een embed mag alleen binnen zijn eigen speler navigeren.
//
// De YouTube-tak toetste dat al op de hóst en legt in het commentaar precies uit
// waarom: met een `contains` glipt `https://youtube.com.kwaadaardig.example/`
// erdoor. De Vimeo-tak ernaast deed het tóch met `contains` — dezelfde
// redenering, op één van de twee takken toegepast.
//
// Deze test bewaakt beide kanten, want de fout hier is niet dat iemand het niet
// wist, maar dat de kennis maar half werd toegepast.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  group('YouTube', () {
    test('de speler en zijn assets mogen', () {
      expect(
        youTubePlayerNavigationAllowed('https://www.youtube-nocookie.com/e/x'),
        isTrue,
      );
      expect(
        youTubePlayerNavigationAllowed('https://i.ytimg.com/vi/x.jpg'),
        isTrue,
      );
      expect(
        youTubePlayerNavigationAllowed('https://r1.googlevideo.com/stream'),
        isTrue,
      );
    });

    test('de trackende kijkpagina mag niet', () {
      // Het YouTube-logo in de speler linkt hierheen: één klik tijdens een
      // presentatie verving de dia door de oorsprong die de nocookie-variant
      // juist moest vermijden.
      expect(
        youTubePlayerNavigationAllowed('https://www.youtube.com/watch?v=x'),
        isFalse,
      );
    });

    test('een host die de naam alleen bevát, mag niet', () {
      expect(
        youTubePlayerNavigationAllowed(
          'https://youtube-nocookie.com.kwaad.example/',
        ),
        isFalse,
      );
      expect(
        youTubePlayerNavigationAllowed('https://kwaad.example/?u=ytimg.com'),
        isFalse,
      );
    });
  });

  group('Vimeo', () {
    test('de speler en zijn assets mogen', () {
      expect(
        vimeoPlayerNavigationAllowed('https://player.vimeo.com/video/1'),
        isTrue,
      );
      expect(vimeoPlayerNavigationAllowed('https://vimeo.com/1'), isTrue);
      expect(
        vimeoPlayerNavigationAllowed('https://i.vimeocdn.com/x.jpg'),
        isTrue,
      );
    });

    test('een host die de naam alleen bevát, mag niet', () {
      // Dit was de bug: `contains('vimeo.com')` liet dit door.
      expect(
        vimeoPlayerNavigationAllowed('https://vimeo.com.kwaadaardig.example/'),
        isFalse,
      );
      expect(
        vimeoPlayerNavigationAllowed('https://kwaad.example/vimeocdn.com/x'),
        isFalse,
      );
    });

    test('rommel wordt geweigerd, niet toegelaten', () {
      // Fail-closed: onparseerbaar is niet hetzelfde als onschuldig.
      expect(vimeoPlayerNavigationAllowed(''), isFalse);
      expect(vimeoPlayerNavigationAllowed('niet eens een url'), isFalse);
      expect(youTubePlayerNavigationAllowed(''), isFalse);
    });
  });
}
