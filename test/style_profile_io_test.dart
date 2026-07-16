import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De bedrading van het los exporteren/importeren van een stijlprofiel: de
/// knoppen in de dialoog, en de belofte dat een import nooit een bestaand
/// profiel overschrijft. Het formaat zelf staat in style_profile_export_test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('de profiel-selector biedt exporteren en importeren', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Het stijlprofiel woont op de Presentatie-tab. Die moet echt geopend
    // worden: een IndexedStack zet de andere tabs offstage en finders slaan
    // offstage widgets standaard over.
    await tester.tap(find.byIcon(Icons.slideshow_outlined));
    await tester.pumpAndSettle();

    // Op icoon, niet op tooltip: die is vertaald en de test draait niet
    // per se in het Nederlands.
    for (final icon in const [
      Icons.file_download_outlined,
      Icons.file_upload_outlined,
    ]) {
      final button = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
      );
      // Aanwezig én bedraad — een knop zonder handler doet niets.
      expect(button.onPressed, isNotNull, reason: '$icon is niet bedraad');
      expect(button.tooltip, isNotEmpty);
    }
  });

  test(
    'een import voegt toe en overschrijft nooit een gelijknamig profiel',
    () async {
      final file = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      SharedPreferences.setMockInitialValues({});
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Een eigen profiel dat al bestaat.
      const mine = ThemeProfile(name: 'Huisstijl', accentColor: '#111111');
      await notifier.saveThemeProfile(mine, previousName: 'Huisstijl');
      final before = notifier.state.themeProfiles.length;

      // Een bestand van iemand anders met dezelfde naam, andere kleur.
      const theirs = ThemeProfile(name: 'Huisstijl', accentColor: '#EE0000');
      final built = await file.buildStyleProfileBytes(theirs);
      final outcome = await file.importStyleProfileBytes(built.bytes);
      expect(outcome.failure, isNull);

      // Zoals de dialoog het doet: previousName matcht bewust niets.
      await notifier.saveThemeProfile(outcome.profile!, previousName: '');

      expect(notifier.state.themeProfiles, hasLength(before + 1));
      // Het eigen profiel is ongemoeid; de import kreeg een unieke naam.
      final kept = notifier.state.themeProfiles.firstWhere(
        (p) => p.name == 'Huisstijl',
      );
      expect(kept.accentColor, '#111111');
      final imported = notifier.state.themeProfile;
      expect(imported.name, isNot('Huisstijl'));
      expect(imported.accentColor, '#EE0000');
    },
  );
}
