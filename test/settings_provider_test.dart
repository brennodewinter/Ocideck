import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a notifier and wait for its async [SettingsNotifier] load to settle.
Future<SettingsNotifier> _loadedNotifier() async {
  SharedPreferences.setMockInitialValues({});
  final notifier = SettingsNotifier();
  // The constructor kicks off an async load; let it complete.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ThemeProfile round-trips the code styling through JSON', () {
    const profile = ThemeProfile(
      codeBackgroundColor: '#000000',
      codeTextColor: '#33FF33',
      codeHighlightSyntax: false,
      codeFontFamily: 'Courier New',
    );
    final back = ThemeProfile.fromJson(profile.toJson());
    expect(back.codeBackgroundColor, '#000000');
    expect(back.codeTextColor, '#33FF33');
    expect(back.codeHighlightSyntax, isFalse);
    expect(back.codeFontFamily, 'Courier New');
  });

  test('ThemeProfile round-trips and clamps the animation duration', () {
    const profile = ThemeProfile(animationDurationMs: 7500);
    expect(ThemeProfile.fromJson(profile.toJson()).animationDurationMs, 7500);
    // Out-of-range values are clamped on load.
    expect(
      ThemeProfile.fromJson(const {
        'animationDurationMs': 999999,
      }).animationDurationMs,
      kThemeMaxAnimationDurationMs,
    );
  });

  test('ThemeProfile animation duration defaults for older decks', () {
    final back = ThemeProfile.fromJson(const {'name': 'Legacy'});
    expect(back.animationDurationMs, kThemeDefaultAnimationDurationMs);
  });

  test('ThemeProfile round-trips checklist styling through JSON', () {
    const profile = ThemeProfile(
      checklistCheckedColor: '#00AA00',
      checklistUncheckedColor: '#CC0000',
      checklistStrikeThrough: false,
    );
    final back = ThemeProfile.fromJson(profile.toJson());
    expect(back.checklistCheckedColor, '#00AA00');
    expect(back.checklistUncheckedColor, '#CC0000');
    expect(back.checklistStrikeThrough, isFalse);
  });

  test('ThemeProfile code styling defaults to the atom-one-dark look', () {
    // Older decks without the fields fall back to the dark editor defaults.
    final back = ThemeProfile.fromJson(const {'name': 'Legacy'});
    expect(back.codeBackgroundColor, '#282C34');
    expect(back.codeTextColor, '#ABB2BF');
    expect(back.codeHighlightSyntax, isTrue);
    expect(back.codeFontFamily, 'monospace');
  });

  test('ThemeProfile.fromJson rejects CSS/HTML-injection colours', () {
    // A theme profile travels inside the deck front matter (base64url JSON) and
    // its colours are interpolated raw into the HTML-export <style> block and
    // the audience-window inline styles. An attacker-supplied value that breaks
    // out of the declaration must be discarded, not carried through.
    final back = ThemeProfile.fromJson(const {
      'accentColor':
          "red}</style><meta http-equiv='refresh' "
          "content='0;url=https://evil/phish'><style>",
      'slideBackgroundColor': 'url(http://evil/?leak)',
      'textColor': '#3366', // too short
    });
    // All fall back to the trusted defaults; the payload never survives.
    expect(back.accentColor, '#2E7D64');
    expect(back.slideBackgroundColor, '#FFFFFF');
    expect(back.textColor, '#222222');
  });

  test('ThemeProfile.fromJson does not inherit a poisoned colour', () {
    // checklistCheckedColor inherits accentColor when absent — the inherited
    // value must be sanitised too, not trusted because it came via the chain.
    final back = ThemeProfile.fromJson(const {
      'accentColor': 'evil}</style><script>x</script>',
    });
    expect(back.accentColor, '#2E7D64');
    expect(back.checklistCheckedColor, '#2E7D64');
    expect(back.tableHeaderBackgroundColor, '#2E7D64');
  });

  test('ThemeProfile.fromJson whitelists font families', () {
    final back = ThemeProfile.fromJson(const {
      'fontFamily': "Arial'}</style><style>",
      'codeFontFamily': "monospace'},body{display:none",
    });
    expect(back.fontFamily, 'Arial');
    expect(back.codeFontFamily, 'monospace');

    // A legitimate offered font is preserved (lossless for real data).
    final ok = ThemeProfile.fromJson(const {
      'fontFamily': 'Georgia',
      'codeFontFamily': 'Menlo',
    });
    expect(ok.fontFamily, 'Georgia');
    expect(ok.codeFontFamily, 'Menlo');
  });

  test('ThemeProfile.fromJson normalises valid colours losslessly', () {
    final back = ThemeProfile.fromJson(const {
      'accentColor': '#2e7d64', // lowercase still accepted
      'titleTextColor': '#FFFFFF',
    });
    expect(back.accentColor, '#2E7D64');
    expect(back.titleTextColor, '#FFFFFF');
  });

  test('ThemeProfile.fromJson sanitises EVERY style field (fuzz)', () {
    // Guards the *class* of bug behind S2: a theme colour/font interpolated
    // raw into the export <style> block (and audience-window inline styles)
    // without validation. Every style field is read back via toJson() and must
    // be a strict #RRGGBB literal or a whitelisted font — never the payload.
    // When a new style field is added, extend the relevant list here (this is
    // the single checklist of CSS-interpolated fields).
    const colorKeys = <String>[
      'slideBackgroundColor',
      'textColor',
      'accentColor',
      'checklistCheckedColor',
      'checklistUncheckedColor',
      'tableTextColor',
      'tableHeaderTextColor',
      'tableHeaderBackgroundColor',
      'titleBackgroundColor',
      'titleTextColor',
      'sectionBackgroundColor',
      'codeBackgroundColor',
      'codeTextColor',
    ];
    const payloads = <String>[
      "red}</style><meta http-equiv='refresh' content='0;url=https://evil'>",
      'url(http://evil/?leak)',
      '#12', // too short
      '#1234ZZ', // non-hex
      'rgb(1,2,3)',
      'expression(alert(1))',
      '',
    ];
    final hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

    for (final key in colorKeys) {
      for (final payload in payloads) {
        final out = ThemeProfile.fromJson({key: payload}).toJson()[key];
        expect(
          out is String && hex.hasMatch(out),
          isTrue,
          reason: 'Colour field "$key" not sanitised for "$payload" → "$out"',
        );
      }
    }

    for (final payload in payloads) {
      final font = ThemeProfile.fromJson({
        'fontFamily': payload,
      }).toJson()['fontFamily'];
      expect(
        AppSettings.availableFonts.contains(font),
        isTrue,
        reason: 'fontFamily not whitelisted for "$payload" → "$font"',
      );
      final codeFont = ThemeProfile.fromJson({
        'codeFontFamily': payload,
      }).toJson()['codeFontFamily'];
      expect(
        AppSettings.codeFonts.contains(codeFont),
        isTrue,
        reason: 'codeFontFamily not whitelisted for "$payload" → "$codeFont"',
      );
    }
  });

  test('starts with a single default profile', () async {
    final notifier = await _loadedNotifier();
    expect(notifier.state.themeProfiles, hasLength(1));
    expect(
      notifier.state.selectedThemeProfileName,
      notifier.state.themeProfiles.single.name,
    );
  });

  test('createThemeProfile adds and selects a new profile', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createThemeProfile();
    expect(notifier.state.themeProfiles, hasLength(2));
    expect(notifier.state.selectedThemeProfileName, created.name);
  });

  test('renaming a profile updates it in place (no duplicate)', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createThemeProfile();

    await notifier.saveThemeProfile(
      created.copyWith(name: 'Mijn stijl'),
      previousName: created.name,
    );

    final names = notifier.state.themeProfiles.map((p) => p.name).toList();
    expect(names, contains('Mijn stijl'));
    expect(
      names,
      isNot(contains(created.name)),
      reason: 'The old name should be replaced, not duplicated',
    );
    expect(notifier.state.themeProfiles, hasLength(2));
    expect(notifier.state.selectedThemeProfileName, 'Mijn stijl');
  });

  test('renaming to an existing name gets a unique suffix', () async {
    final notifier = await _loadedNotifier();
    final defaultName = notifier.state.themeProfiles.single.name;
    final created = await notifier.createThemeProfile();

    await notifier.saveThemeProfile(
      created.copyWith(name: defaultName),
      previousName: created.name,
    );

    final names = notifier.state.themeProfiles.map((p) => p.name).toList();
    expect(names, contains(defaultName));
    expect(names, contains('$defaultName 2'));
    expect(names.toSet(), hasLength(names.length), reason: 'names are unique');
  });

  test('editing colors persists without losing the profile name', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createThemeProfile();

    await notifier.saveThemeProfile(
      created.copyWith(name: 'Klant A', accentColor: '#FF0000'),
      previousName: created.name,
    );

    final profile = notifier.state.themeProfiles.firstWhere(
      (p) => p.name == 'Klant A',
    );
    expect(profile.accentColor, '#FF0000');
    expect(notifier.state.themeProfile.name, 'Klant A');
  });

  test('deleteThemeProfile removes it and selects another', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createThemeProfile();
    expect(notifier.state.themeProfiles, hasLength(2));

    await notifier.deleteThemeProfile(created.name);

    final names = notifier.state.themeProfiles.map((p) => p.name).toList();
    expect(names, isNot(contains(created.name)));
    expect(notifier.state.themeProfiles, hasLength(1));
    expect(notifier.state.selectedThemeProfileName, names.single);
  });

  test('never deletes the last remaining profile', () async {
    final notifier = await _loadedNotifier();
    final only = notifier.state.themeProfiles.single.name;
    await notifier.deleteThemeProfile(only);
    expect(notifier.state.themeProfiles, hasLength(1));
  });

  test('starts with Basic, Europa and Donker app themes', () async {
    final notifier = await _loadedNotifier();
    expect(
      notifier.state.appAppearanceProfiles.map((profile) => profile.name),
      containsAll(['Basic', 'Europa', 'Donker']),
    );
    expect(notifier.state.selectedAppAppearanceProfileName, 'Basic');
  });

  test('creates, edits and selects a custom app theme', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createAppAppearanceProfile(
      base: AppAppearanceProfile.europa,
    );

    await notifier.saveAppAppearanceProfile(
      created.copyWith(name: 'Mijn Europa', accentColor: '#FFE000'),
      previousName: created.name,
    );

    expect(notifier.state.selectedAppAppearanceProfileName, 'Mijn Europa');
    expect(notifier.state.appAppearanceProfile.accentColor, '#FFE000');
    expect(notifier.state.appAppearanceProfile.isBuiltIn, isFalse);
  });

  test('built-in app themes cannot be deleted', () async {
    final notifier = await _loadedNotifier();
    await notifier.deleteAppAppearanceProfile('Europa');
    expect(
      notifier.state.appAppearanceProfiles.map((profile) => profile.name),
      contains('Europa'),
    );
  });

  group('simple settings setters', () {
    test('export TLP bounds set and clear', () async {
      final n = await _loadedNotifier();
      await n.setMaxReleaseExportTlp('amber');
      await n.setMinRequiredExportTlp('green');
      expect(n.state.maxReleaseExportTlpKey, 'amber');
      expect(n.state.minRequiredExportTlpKey, 'green');

      await n.setMaxReleaseExportTlp(null);
      await n.setMinRequiredExportTlp(null);
      expect(n.state.maxReleaseExportTlpKey, isNull);
      expect(n.state.minRequiredExportTlpKey, isNull);
    });

    test('classification and quality export toggles', () async {
      final n = await _loadedNotifier();
      await n.setRequireClassificationOnExport(true);
      await n.setClassificationWatermarkEnabled(true);
      await n.setQualityWarningsOnExport(false);
      await n.setQualityBlockExportOnErrors(true);
      expect(n.state.requireClassificationOnExport, isTrue);
      expect(n.state.classificationWatermarkEnabled, isTrue);
      expect(n.state.qualityWarningsOnExport, isFalse);
      expect(n.state.qualityBlockExportOnErrors, isTrue);
    });

    test('uiTextScale is clamped to 1.0..2.0', () async {
      final n = await _loadedNotifier();
      await n.setUiTextScale(5);
      expect(n.state.uiTextScale, 2.0);
      await n.setUiTextScale(0.1);
      expect(n.state.uiTextScale, 1.0);
      await n.setUiTextScale(1.5);
      expect(n.state.uiTextScale, 1.5);
    });

    test('contrastMinRatio defaults to WCAG AA, persists and clamps', () async {
      final n = await _loadedNotifier();
      expect(n.state.contrastMinRatio, 4.5);
      await n.setContrastMinRatio(3.5);
      expect(n.state.contrastMinRatio, 3.5);
      await n.setContrastMinRatio(99);
      expect(n.state.contrastMinRatio, 7.0);
      await n.setContrastMinRatio(0.1);
      expect(n.state.contrastMinRatio, 1.0);
    });

    test('allowRemoteMedia and languageCode persist', () async {
      final n = await _loadedNotifier();
      await n.setAllowRemoteMedia(true);
      await n.setLanguageCode('fy');
      expect(n.state.allowRemoteMedia, isTrue);
      expect(n.state.languageCode, 'fy');
    });

    test(
      'addRecentFile de-duplicates, keeps newest first, caps at 10',
      () async {
        final n = await _loadedNotifier();
        for (var i = 0; i < 12; i++) {
          await n.addRecentFile('/deck_$i.md');
        }
        // Re-adding an existing path moves it to the front without duplicating.
        await n.addRecentFile('/deck_5.md');
        final recent = n.state.recentFiles;
        expect(recent, hasLength(10));
        expect(recent.first, '/deck_5.md');
        expect(recent.where((p) => p == '/deck_5.md'), hasLength(1));
      },
    );

    test('home and export directories set and clear', () async {
      final n = await _loadedNotifier();
      await n.setHomeDirectory('/home/decks');
      await n.setExportDirectory('/export');
      expect(n.state.homeDirectory, '/home/decks');
      expect(n.state.exportDirectory, '/export');

      await n.setHomeDirectory(null);
      await n.setExportDirectory(null);
      expect(n.state.homeDirectory, isNull);
      expect(n.state.exportDirectory, isNull);
    });
  });

  group('app interface font', () {
    const custom = AppAppearanceProfile(
      name: 'Eigen',
      primaryColor: '#000000',
      accentColor: '#111111',
      backgroundColor: '#222222',
      surfaceColor: '#333333',
      textColor: '#444444',
      mutedTextColor: '#555555',
      panelColor: '#666666',
      panelTextColor: '#777777',
      fontFamily: 'Inter',
    );

    test('offered UI fonts are the bundled families', () {
      expect(
        AppAppearanceProfile.uiFonts,
        containsAll(<String>['Roboto', 'Inter', 'Lora', 'EB Garamond']),
      );
      expect(AppAppearanceProfile.basic.fontFamily, 'Roboto');
    });

    test('fontFamily round-trips and copyWith updates it', () {
      expect(
        AppAppearanceProfile.fromJson(custom.toJson()).fontFamily,
        'Inter',
      );
      expect(custom.copyWith(fontFamily: 'Lora').fontFamily, 'Lora');
      // Legacy JSON without the field falls back to Roboto.
      final legacy = AppAppearanceProfile.fromJson(
        Map<String, Object?>.from(custom.toJson())..remove('fontFamily'),
      );
      expect(legacy.fontFamily, 'Roboto');
    });

    test('saving a custom app theme persists its font', () async {
      final notifier = await _loadedNotifier();
      final created = await notifier.createAppAppearanceProfile(
        base: AppAppearanceProfile.basic,
      );
      await notifier.saveAppAppearanceProfile(
        created.copyWith(name: 'Lettertype-thema', fontFamily: 'Lora'),
        previousName: created.name,
      );
      expect(notifier.state.appAppearanceProfile.fontFamily, 'Lora');
    });
  });
}
