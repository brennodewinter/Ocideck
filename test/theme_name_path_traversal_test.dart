import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

/// A deck's `theme:` front matter is attacker-controlled. Saving must never let
/// it escape the project's `themes/` directory (the CSS is app-generated, but
/// an arbitrary `.css` path outside the project could still be overwritten).
void main() {
  // Needed so rootBundle can load assets/themes/ocideck.css → _writeTheme
  // actually writes the theme CSS instead of skipping on a missing asset.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('malicious theme name cannot escape the project themes/ dir', () async {
    final tmp = await Directory.systemTemp.createTemp('ocideck_theme_');
    addTearDown(() => tmp.delete(recursive: true));

    final projectDir = Directory(p.join(tmp.path, 'project'))
      ..createSync(recursive: true);
    // A canary the traversal payload ("../../evil") would target if it escaped.
    final canary = File(p.join(tmp.path, 'evil.css'))..writeAsStringSync('SAFE');

    final fs = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final deck = Deck(
      title: 'T',
      theme: '../../evil',
      slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
    );

    await fs.saveDeck(deck, p.join(projectDir.path, 'deck.md'));

    // The canary outside the project is untouched.
    expect(canary.readAsStringSync(), 'SAFE');

    // The theme CSS landed inside the project themes/ dir under a sanitised
    // name (../../evil → evil), nothing containing traversal segments.
    final themesDir = Directory(p.join(projectDir.path, 'themes'));
    expect(themesDir.existsSync(), isTrue);
    final written = themesDir.listSync().whereType<File>().toList();
    expect(written, isNotEmpty, reason: 'theme CSS should have been written');
    for (final f in written) {
      expect(p.isWithin(themesDir.path, f.path), isTrue);
      expect(p.basename(f.path), isNot(contains('..')));
    }
    expect(File(p.join(themesDir.path, 'evil.css')).existsSync(), isTrue);
  });
}
