import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/launch_files.dart';

void main() {
  test('alleen presentatie-extensies gelden als launch-bestand', () {
    expect(looksLikeDeckLaunchArg(r'C:\Decks\demo.ocideck'), isTrue);
    expect(looksLikeDeckLaunchArg('/tmp/demo.md'), isTrue);
    expect(looksLikeDeckLaunchArg('pakket.ZIP'), isTrue);
    // Flags, andere bestanden en lege argumenten nooit.
    expect(looksLikeDeckLaunchArg('--verbose'), isFalse);
    expect(looksLikeDeckLaunchArg('multi_window'), isFalse);
    expect(looksLikeDeckLaunchArg('foto.png'), isFalse);
    expect(looksLikeDeckLaunchArg(''), isFalse);
  });

  test('deckDeepLinkFrom leest ?deck= en negeert lege waarden', () {
    expect(
      deckDeepLinkFrom(
        Uri.parse(
          'https://ocideck.example/?deck=https%3A%2F%2Felders.example%2Fd.md',
        ),
      ),
      'https://elders.example/d.md',
    );
    expect(
      deckDeepLinkFrom(Uri.parse('https://ocideck.example/?deck=%20%20')),
      isNull,
    );
    expect(deckDeepLinkFrom(Uri.parse('https://ocideck.example/')), isNull);
    // Andere parameters blijven onaangeroerd.
    expect(
      deckDeepLinkFrom(Uri.parse('https://ocideck.example/?taal=nl')),
      isNull,
    );
  });

  test('deckDeepLinkFrom geeft een gecodeerde bron met eigen query en '
      'fragment volledig terug (#2826)', () {
    // Precies de waarde die afbrak toen hem iemand ongecodeerd in de link
    // zette: de &-tekens van de bron lazen als nieuwe parameters van de app.
    final link = Uri.parse(
      'https://ocideck.example/?deck='
      'https%3A%2F%2Felders.example%2Fzoek%3Fq%3Dkat%26n%3D5%23kop',
    );
    expect(deckDeepLinkFrom(link), 'https://elders.example/zoek?q=kat&n=5#kop');
  });

  test('withoutDeckParam wist alleen de deck-parameter (#2826)', () {
    final uri = Uri.parse(
      'https://ocideck.example/app/?deck=https%3A%2F%2Fe.x%2Fd.md&taal=nl',
    );
    expect(
      withoutDeckParam(uri).toString(),
      'https://ocideck.example/app/?taal=nl',
    );
    // Was deck de enige parameter, dan valt ook het vraagteken weg.
    expect(
      withoutDeckParam(
        Uri.parse('https://ocideck.example/?deck=https%3A%2F%2Fe.x%2Fd.md'),
      ).toString(),
      'https://ocideck.example/',
    );
  });

  test('deckShareLink codeert de bron volledig (#2826)', () {
    final base = Uri.parse('https://ocideck.example/app/');
    expect(
      deckShareLink(base, 'https://elders.example/zoek?q=kat&n=5#kop'),
      'https://ocideck.example/app/'
      '?deck=https%3A%2F%2Felders.example%2Fzoek%3Fq%3Dkat%26n%3D5%23kop',
    );
    // En de ronde terug levert de bron weer heel op.
    final link = Uri.parse(deckShareLink(base, 'https://e.x/d.md'));
    expect(deckDeepLinkFrom(link), 'https://e.x/d.md');
  });
}
