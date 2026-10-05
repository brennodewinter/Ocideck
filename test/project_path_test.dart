import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/project_path.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolveProjectRelative', () {
    test('resolves a normal relative path inside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveProjectRelative(project, 'images/photo.png'),
        p.normalize(p.join(project, 'images', 'photo.png')),
      );
    });

    test('rejects path traversal via ../', () {
      final project = p.join('/tmp', 'deck');
      expect(resolveProjectRelative(project, '../secret.txt'), isNull);
    });

    test('rejects absolute paths', () {
      expect(resolveProjectRelative('/tmp/deck', '/etc/passwd'), isNull);
    });

    test('rejects empty path or missing base', () {
      expect(resolveProjectRelative('/tmp/deck', ''), isNull);
      expect(resolveProjectRelative(null, 'images/a.png'), isNull);
    });
  });

  group('resolveSlideAssetPath', () {
    test('blocks absolute paths outside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(resolveSlideAssetPath('/etc/passwd', project), isNull);
    });

    test('allows absolute paths inside the project', () {
      final project = p.join('/tmp', 'deck');
      final inside = p.join(project, 'images', 'photo.png');
      expect(resolveSlideAssetPath(inside, project), p.normalize(inside));
    });

    test('allows absolute paths when the deck is unsaved', () {
      expect(
        resolveSlideAssetPath('/tmp/pasted.png', null),
        p.normalize('/tmp/pasted.png'),
      );
    });

    test('blocks relative traversal for saved decks', () {
      final project = p.join('/tmp', 'deck');
      expect(resolveSlideAssetPath('../../etc/passwd', project), isNull);
    });
  });

  group('resolveTrustedAssetPath', () {
    test('allows an absolute logo outside the opened deck project', () {
      // The style-profile logo lives in the user's regular folder; opening a
      // deck elsewhere must still resolve it (it is trusted app config).
      final project = p.join('/tmp', 'other-deck');
      final logo = p.join('/tmp', 'regular', 'logos', 'logo.png');
      expect(resolveTrustedAssetPath(logo, project), p.normalize(logo));
    });

    test('still resolves a relative logo inside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveTrustedAssetPath('logos/logo.png', project),
        p.normalize(p.join(project, 'logos', 'logo.png')),
      );
    });

    test('rejects relative traversal even for trusted assets', () {
      final project = p.join('/tmp', 'deck');
      expect(resolveTrustedAssetPath('../../etc/passwd', project), isNull);
    });

    test('empty path resolves to null', () {
      expect(resolveTrustedAssetPath('', p.join('/tmp', 'deck')), isNull);
    });
  });

  group('resolveDeckAssetUrl', () {
    const deckUrl = 'https://deck.example/decks/presentatie.md';

    test('resolves a relative path against the deck URL directory', () {
      expect(
        resolveDeckAssetUrl('images/foto.png', deckUrl),
        'https://deck.example/decks/images/foto.png',
      );
    });

    test('resolves ./-prefixed and nested relative paths', () {
      expect(
        resolveDeckAssetUrl('./images/foto.png', deckUrl),
        'https://deck.example/decks/images/foto.png',
      );
      expect(
        resolveDeckAssetUrl('a/b/c.png', deckUrl),
        'https://deck.example/decks/a/b/c.png',
      );
    });

    test('keeps query and fragment of the deck URL out of the base', () {
      expect(
        resolveDeckAssetUrl(
          'i.png',
          'https://deck.example/decks/presentatie.md?v=2#s1',
        ),
        'https://deck.example/decks/i.png',
      );
    });

    test('keeps a non-default port', () {
      expect(
        resolveDeckAssetUrl('i.png', 'https://deck.example:8443/d/p.md'),
        'https://deck.example:8443/d/i.png',
      );
    });

    test('rejects .. escaping the deck directory', () {
      expect(resolveDeckAssetUrl('../geshared/x.png', deckUrl), isNull);
      expect(resolveDeckAssetUrl('images/../../x.png', deckUrl), isNull);
      // Percent-encoded separators decode to real traversal — the containment
      // check runs on the decoded path.
      expect(resolveDeckAssetUrl('..%2F..%2Fetc/passwd', deckUrl), isNull);
    });

    test('rejects references with their own scheme or authority', () {
      expect(
        resolveDeckAssetUrl('https://ander.example/x.png', deckUrl),
        isNull,
      );
      expect(resolveDeckAssetUrl('//ander.example/x.png', deckUrl), isNull);
      expect(resolveDeckAssetUrl('data:image/png;base64,xx', deckUrl), isNull);
      expect(resolveDeckAssetUrl('mem:abc123', deckUrl), isNull);
      expect(resolveDeckAssetUrl('asset:logo.png', deckUrl), isNull);
    });

    test('rejects root-absolute paths outside the deck directory', () {
      expect(resolveDeckAssetUrl('/images/x.png', deckUrl), isNull);
      // Een deck in de documentroot mag wél naar /images/ verwijzen.
      expect(
        resolveDeckAssetUrl('/images/x.png', 'https://deck.example/p.md'),
        'https://deck.example/images/x.png',
      );
    });

    test('rejects a missing or non-http deck URL', () {
      expect(resolveDeckAssetUrl('i.png', null), isNull);
      expect(resolveDeckAssetUrl('i.png', ''), isNull);
      expect(resolveDeckAssetUrl('i.png', 'geen-url'), isNull);
      expect(resolveDeckAssetUrl('i.png', 'ftp://h/d/p.md'), isNull);
      expect(resolveDeckAssetUrl('i.png', 'file:///d/p.md'), isNull);
      expect(resolveDeckAssetUrl('i.png', '/decks/p.md'), isNull);
    });

    test('rejects an empty asset path', () {
      expect(resolveDeckAssetUrl('', deckUrl), isNull);
      expect(resolveDeckAssetUrl('   ', deckUrl), isNull);
      expect(resolveDeckAssetUrl(null, deckUrl), isNull);
    });
  });

  group('remoteDeckUrlOrNull', () {
    test('keeps absolute http(s) URLs, normalised', () {
      expect(
        remoteDeckUrlOrNull('https://deck.example/decks/p.md'),
        'https://deck.example/decks/p.md',
      );
      expect(
        remoteDeckUrlOrNull('  http://deck.example/d/p.md '),
        'http://deck.example/d/p.md',
      );
    });

    test('rejects git labels, file paths and non-http schemes', () {
      expect(remoteDeckUrlOrNull('git: LibreKAT/Ocideck @ main'), isNull);
      expect(remoteDeckUrlOrNull('/tmp/deck.md'), isNull);
      expect(remoteDeckUrlOrNull('file:///tmp/deck.md'), isNull);
      expect(remoteDeckUrlOrNull('ftp://h/d.md'), isNull);
      expect(remoteDeckUrlOrNull(null), isNull);
      expect(remoteDeckUrlOrNull(''), isNull);
    });
  });

  group('resolveEditorAssetPath', () {
    test('joins relative paths safely for the editor', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveEditorAssetPath('images/a.png', project),
        p.normalize(p.join(project, 'images', 'a.png')),
      );
    });

    test('still resolves user-picked absolute paths outside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveEditorAssetPath('/Users/me/photo.png', project),
        p.normalize('/Users/me/photo.png'),
      );
    });
  });
}
