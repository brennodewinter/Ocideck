import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('end-to-end: edit → save → reopen → toggle → save → export', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_e2e_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final md = MarkdownService();
    final file = FileService(md, ImageService(), () => const ThemeProfile());
    final mdPath = p.join(temp.path, 'talk.md');
    final notifier = DeckNotifier(md, file);

    // Open an in-memory deck and edit it.
    notifier.loadDeck(
      Deck(
        title: 'Talk',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Welkom'),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Agenda', bullets: ['een', 'twee']),
        ],
      ),
      filePath: mdPath,
    );
    notifier.updateSlide(
      0,
      notifier.state.deck!.slides[0].copyWith(title: 'Welkom allemaal'),
    );

    // Save through the real provider → FileService path (atomic write).
    expect(await notifier.save(), isTrue);
    expect(notifier.state.isDirty, isFalse);
    expect(await File(mdPath).exists(), isTrue);

    // Reopen from disk and confirm the edit survived the round-trip.
    final reopened = await file.openDeck(mdPath);
    expect(reopened, isNotNull);
    expect(reopened!.slides.first.title, 'Welkom allemaal');
    expect(reopened.slides[1].bullets, ['een', 'twee']);

    // Toggle through markdown mode and back, then edit and save again.
    final buffer = notifier.generateMarkdown();
    expect(notifier.applyMarkdown(buffer), isTrue);
    notifier.updateSlide(
      1,
      notifier.state.deck!.slides[1].copyWith(title: 'Programma'),
    );
    expect(await notifier.save(), isTrue);

    // Export the saved deck to self-contained HTML.
    final exportService = ExportService();
    final result = await exportService.export(
      mdPath,
      ExportFormat.html,
      const <Uint8List>[],
      markdown: md.generateDeck(notifier.state.deck!),
      outputDirectory: temp.path,
    );

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, isNotNull);
    final out = File(result.outputPath!);
    expect(await out.exists(), isTrue);
    final html = await out.readAsString();
    expect(html, contains('Welkom allemaal'));
    expect(html, contains('Programma'));
  });
}
