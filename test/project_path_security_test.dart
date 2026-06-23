import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/project_path.dart';

/// Locks the containment guarantee that protects against a malicious deck (.md)
/// referencing files outside its project directory via absolute or `../` asset
/// paths. If any of these start returning a non-null escaping path, a crafted
/// deck could make a file-reading sink (preview/export/clipboard) read an
/// arbitrary file.
void main() {
  const project = '/home/user/Presentations/Deck';

  group('resolveSlideAssetPath containment (deck opened from disk)', () {
    test('rejects parent-traversal escapes', () {
      expect(resolveSlideAssetPath('../../../etc/passwd', project), isNull);
      expect(resolveSlideAssetPath('images/../../secret.png', project), isNull);
    });

    test('rejects absolute paths outside the project', () {
      expect(resolveSlideAssetPath('/etc/passwd', project), isNull);
      expect(
        resolveSlideAssetPath('/home/user/.ssh/id_rsa', project),
        isNull,
      );
    });

    test('allows project-contained relative and absolute paths', () {
      expect(
        resolveSlideAssetPath('images/cover.png', project),
        '$project/images/cover.png',
      );
      expect(
        resolveSlideAssetPath('$project/images/cover.png', project),
        '$project/images/cover.png',
      );
    });
  });

  // Note: resolveEditorAssetPath is intentionally permissive (the editor must
  // display user-picked images from anywhere on disk). Security-sensitive sinks
  // such as copy-to-clipboard deliberately use resolveSlideAssetPath above
  // instead, so a deck opened from disk can't exfiltrate an arbitrary file.
}
