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
}
