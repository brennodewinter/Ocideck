// De transcript-meldingstrook (#2511): ontbrekende audio is een herstelbare
// melding met het transcript intact; een beschadigde marker degradeert naar
// gewone tekst met uitleg.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/panels/transcript_notice.dart';
import 'package:path/path.dart' as p;

const _withAudio =
    '<!-- transcript version=1 audio="media/opname.wav" -->\n'
    '# Transcript — gesprek\n'
    '\n'
    'Bron: [opname.wav](media/opname.wav)\n'
    '\n'
    '---\n'
    '\n'
    'De tekst.\n';

Widget _app({required String source, String? projectPath}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: TranscriptNotice(source: source, projectPath: projectPath),
  ),
);

void main() {
  late Directory dir;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = Directory.systemTemp.createTempSync('transcript_notice');
    Directory(p.join(dir.path, 'media')).createSync();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('geen transcript → geen strook', (tester) async {
    await tester.pumpWidget(
      _app(source: '# Gewoon\n\nTekst.\n', projectPath: dir.path),
    );
    expect(find.byType(TranscriptNotice), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('ontbrekende audio toont een melding, tekst blijft', (
    tester,
  ) async {
    await tester.pumpWidget(_app(source: _withAudio, projectPath: dir.path));
    await tester.pump();
    expect(
      find.textContaining('audiobestand is verplaatst of verwijderd'),
      findsOneWidget,
    );
    // Herstelbaar: de knop kijkt opnieuw.
    expect(find.byTooltip('Opnieuw controleren'), findsOneWidget);
  });

  testWidgets('teruggezette audio dooft de melding via opnieuw controleren', (
    tester,
  ) async {
    await tester.pumpWidget(_app(source: _withAudio, projectPath: dir.path));
    await tester.pump();
    File(p.join(dir.path, 'media', 'opname.wav')).writeAsBytesSync([0]);
    await tester.tap(find.byTooltip('Opnieuw controleren'));
    await tester.pump();
    expect(
      find.textContaining('audiobestand is verplaatst of verwijderd'),
      findsNothing,
    );
  });

  testWidgets('aanwezige audio toont geen strook', (tester) async {
    File(p.join(dir.path, 'media', 'opname.wav')).writeAsBytesSync([0]);
    await tester.pumpWidget(_app(source: _withAudio, projectPath: dir.path));
    await tester.pump();
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('beschadigde marker wordt gemeld', (tester) async {
    await tester.pumpWidget(
      _app(source: '<!-- transcript -->\n# T\n', projectPath: dir.path),
    );
    await tester.pump();
    expect(
      find.textContaining('transcript-marker is beschadigd'),
      findsOneWidget,
    );
  });
}
