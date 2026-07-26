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
