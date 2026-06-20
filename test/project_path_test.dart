import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/project_path.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolveProjectRelative', () {
    test('resolves a normal relative path inside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveProjectRelative(project, 'images/photo.png'),
        p.join(project, 'images', 'photo.png'),
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
      expect(resolveSlideAssetPath(inside, project), inside);
    });

    test('allows absolute paths when the deck is unsaved', () {
      expect(
        resolveSlideAssetPath('/tmp/pasted.png', null),
        '/tmp/pasted.png',
      );
    });

    test('blocks relative traversal for saved decks', () {
      final project = p.join('/tmp', 'deck');
      expect(resolveSlideAssetPath('../../etc/passwd', project), isNull);
    });
  });

  group('resolveEditorAssetPath', () {
    test('joins relative paths safely for the editor', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveEditorAssetPath('images/a.png', project),
        p.join(project, 'images', 'a.png'),
      );
    });

    test('still resolves user-picked absolute paths outside the project', () {
      final project = p.join('/tmp', 'deck');
      expect(
        resolveEditorAssetPath('/Users/me/photo.png', project),
        '/Users/me/photo.png',
      );
    });
  });
}
