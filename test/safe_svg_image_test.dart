import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/utils/project_path.dart';
import 'package:ocideck/utils/sanitize_svg.dart';
import 'package:ocideck/widgets/safe_svg_image.dart';
import 'package:path/path.dart' as p;

import 'support/pump_until.dart';

void main() {
  setUp(debugResetSvgCache);

  testWidgets('tekent een opgeschoonde SVG als vectorbeeld', (tester) async {
    final bytes = Uint8List.fromList(
      '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>'.codeUnits,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SafeSvgImage.memory(
          bytes,
          errorBuilder: (_) => const Text('kapot'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('kapot'), findsNothing);
  });

  testWidgets('ongeldige SVG toont dezelfde foutweergave als raster', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SafeSvgImage.memory(
          Uint8List.fromList('<svg><broken>'.codeUnits),
          errorBuilder: (_) => const Text('kapot'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('kapot'), findsOneWidget);
  });

  testWidgets('SVG-wrapper met PNG gebruikt het betrouwbare rasterpad', (
    tester,
  ) async {
    final png = img.encodePng(img.Image(width: 2, height: 2));
    final svg =
        '<svg width="2" height="2"><image width="2" height="2" '
        'href="data:image/png;base64,${base64.encode(png)}"/></svg>';

    await tester.pumpWidget(
      MaterialApp(
        home: SafeSvgImage.memory(
          Uint8List.fromList(utf8.encode(svg)),
          errorBuilder: (_) => const Text('kapot'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('kapot'), findsNothing);
  });

  testWidgets('SVG-bestandslezer blokkeert een symlink buiten het project', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('ocideck_svg_symlink');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final project = Directory(p.join(tmp.path, 'deck'))..createSync();
    final images = Directory(p.join(project.path, 'images'))..createSync();
    final outside = File(p.join(tmp.path, 'outside.svg'))
      ..writeAsStringSync(
        '<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
      );
    final link = Link(p.join(images.path, 'escape.svg'))
      ..createSync(outside.path);

    await tester.pumpWidget(
      MaterialApp(
        home: SafeSvgImage.file(
          link.path,
          projectPath: project.path,
          errorBuilder: (_) => const Text('kapot'),
          errorBuilderWithCause: (_, error) =>
              Text(error is ProjectEscapeException ? 'buiten' : 'kapot'),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('buiten').evaluate().isNotEmpty,
      reason: 'een symlink-escape moet als buiten-de-deck renderen',
    );

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('buiten'), findsOneWidget);
  });

  testWidgets('hetzelfde bestand wordt maar één keer opgeschoond (#2682)', (
    tester,
  ) async {
    debugResetSvgCache();
    final tmp = Directory.systemTemp.createTempSync('ocideck_svg_cache');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File(p.join(tmp.path, 'teken.svg'))
      ..writeAsStringSync(
        '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>',
      );

    Widget image() => SafeSvgImage.file(
      file.path,
      width: 40,
      height: 40,
      errorBuilder: (_) => const Text('kapot'),
    );

    await tester.pumpWidget(
      MaterialApp(home: Column(children: [image(), image()])),
    );
    await pumpUntil(
      tester,
      () => find.byType(SvgPicture).evaluate().length == 2,
    );

    expect(debugImportedSvgSanitizeCount, 1);
  });

  testWidgets(
    'wisselen van dia met dezelfde SVG toont geen leeg vlak (#2682)',
    (tester) async {
      debugResetSvgCache();
      final tmp = Directory.systemTemp.createTempSync('ocideck_svg_switch');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final file = File(p.join(tmp.path, 'teken.svg'))
        ..writeAsStringSync(
          '<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
        );
      var slide = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => slide += 1),
                  child: const Text('volgende'),
                ),
                KeyedSubtree(
                  key: ValueKey(slide),
                  child: SafeSvgImage.file(
                    file.path,
                    width: 40,
                    height: 40,
                    errorBuilder: (_) => const Text('kapot'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(SvgPicture).evaluate().isNotEmpty,
      );

      await tester.tap(find.text('volgende'));
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('kapot'), findsNothing);
    },
  );
}
