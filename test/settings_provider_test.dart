import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart' show TlpLevel;
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/secret_store.dart';
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

  test('starts with the built-in profiles, LibreKAT selected', () async {
    final notifier = await _loadedNotifier();
    expect(notifier.state.themeProfiles, hasLength(3));
    expect(
      notifier.state.themeProfiles.map((p) => p.name),
      containsAll(['LibreKAT', 'Standaard', 'Security']),
    );
    expect(notifier.state.selectedThemeProfileName, 'LibreKAT');
    // Het LibreKAT-logo is een gebundelde asset zodat het overal (ook web)
    // rendert en mee kan in pakket-exports.
    expect(
      notifier.state.themeProfile.logoPath,
      'asset:assets/images/librekat-logo.png',
    );
  });

  test('createThemeProfile adds and selects a new profile', () async {
    final notifier = await _loadedNotifier();
    final created = await notifier.createThemeProfile();
    expect(notifier.state.themeProfiles, hasLength(4));
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
    expect(notifier.state.themeProfiles, hasLength(4));
    expect(notifier.state.selectedThemeProfileName, 'Mijn stijl');
  });

  test('renaming to an existing name gets a unique suffix', () async {
    final notifier = await _loadedNotifier();
    final defaultName = notifier.state.themeProfiles.first.name;
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
    expect(notifier.state.themeProfiles, hasLength(4));

    await notifier.deleteThemeProfile(created.name);

    final names = notifier.state.themeProfiles.map((p) => p.name).toList();
    expect(names, isNot(contains(created.name)));
    expect(notifier.state.themeProfiles, hasLength(3));
    expect(notifier.state.selectedThemeProfileName, names.first);
  });

  test('never deletes the last remaining profile', () async {
    final notifier = await _loadedNotifier();
    for (final name
        in notifier.state.themeProfiles.map((p) => p.name).toList()) {
      await notifier.deleteThemeProfile(name);
    }
    expect(notifier.state.themeProfiles, hasLength(1));
  });

  test('starts with Basic, Europa and Donker app themes', () async {
    final notifier = await _loadedNotifier();
    expect(
      notifier.state.appAppearanceProfiles.map((profile) => profile.name),
      containsAll(['Basic', 'Europa', 'Donker']),
    );
    expect(notifier.state.selectedAppAppearanceProfileName, 'Europa');
  });

  test('landing a custom app theme selects and persists it', () async {
    // Sinds #760 landt het instellingenvenster zijn hele werkkopie in één
    // keer; de losse create/save/delete-wegen bestaan niet meer.
    final notifier = await _loadedNotifier();
    final custom = AppAppearanceProfile.europa.copyWith(
      name: 'Mijn Europa',
      accentColor: '#FFE000',
      isBuiltIn: false,
    );

    await notifier.setAppAppearanceProfiles([
      ...notifier.state.appAppearanceProfiles,
      custom,
    ], selectedName: 'Mijn Europa');

    expect(notifier.state.selectedAppAppearanceProfileName, 'Mijn Europa');
    expect(notifier.state.appAppearanceProfile.accentColor, '#FFE000');
    expect(notifier.state.appAppearanceProfile.isBuiltIn, isFalse);
  });

  test('built-in app themes survive whatever the caller lands', () async {
    // Wat de werkkopie ook aanlevert — zonder ingebouwde thema's, of met een
    // "aangepaste" kopie die zich ingebouwd noemt — de ingebouwde drie komen
    // uit de eigen staat en blijven staan.
    final notifier = await _loadedNotifier();
    await notifier.setAppAppearanceProfiles(const [], selectedName: 'Europa');
    expect(
      notifier.state.appAppearanceProfiles.map((profile) => profile.name),
      containsAll(['Basic', 'Europa', 'Donker']),
    );
  });

  test('an unknown selection falls back to an existing theme', () async {
    final notifier = await _loadedNotifier();
    await notifier.setAppAppearanceProfiles(
      const [],
      selectedName: 'Bestaat niet',
    );
    expect(
      notifier.state.appAppearanceProfiles.map((profile) => profile.name),
      contains(notifier.state.selectedAppAppearanceProfileName),
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

    test('docReaderTextScale defaults to 1.0, persists and clamps', () async {
      final n = await _loadedNotifier();
      expect(n.state.docReaderTextScale, 1.0);
      await n.setDocReaderTextScale(5);
      expect(
        n.state.docReaderTextScale,
        SettingsNotifier.docReaderTextScaleMax,
      );
      await n.setDocReaderTextScale(0.1);
      expect(
        n.state.docReaderTextScale,
        SettingsNotifier.docReaderTextScaleMin,
      );
      await n.setDocReaderTextScale(1.3);
      expect(n.state.docReaderTextScale, 1.3);
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
        expect(recent.first.path, '/deck_5.md');
        expect(recent.where((f) => f.path == '/deck_5.md'), hasLength(1));
      },
    );

    test('addRecentFile ververst metadata en bewaart export-info', () async {
      final n = await _loadedNotifier();
      await n.addRecentFile('/deck.md', slideCount: 12, tlp: TlpLevel.amber);
      await n.recordRecentFileExport('/deck.md', 'PDF');
      // Opnieuw openen: metadata vers, export-registratie blijft staan.
      await n.addRecentFile('/deck.md', slideCount: 14, tlp: TlpLevel.green);
      final entry = n.state.recentFiles.single;
      expect(entry.slideCount, 14);
      expect(entry.tlp, TlpLevel.green);
      expect(entry.openedAt, isNotNull);
      expect(entry.lastExportFormat, 'PDF');
      expect(entry.lastExportAt, isNotNull);
    });

    test('addRecentFile onthoudt de soort document (regressie)', () async {
      // Een document dat via Opslaan-als / openen in de recente lijst belandt,
      // moet als document worden onthouden — anders leest het heropenen weer
      // "presentatie" en verliest de lijst het onderscheid. Vóór de fix werd
      // `kind` niet doorgegeven (tabs_provider: "latere politoer").
      final n = await _loadedNotifier();
      await n.addRecentFile('/memo.md', kind: MarkdownKind.document);
      expect(n.state.recentFiles.single.kind, MarkdownKind.document);

      // Zonder soort blijft een pad een presentatie (de veilige standaard).
      await n.addRecentFile('/deck.md');
      final deck = n.state.recentFiles.firstWhere((f) => f.path == '/deck.md');
      expect(deck.kind, MarkdownKind.presentation);
    });

    test('recordRecentFileExport negeert onbekende paden', () async {
      final n = await _loadedNotifier();
      await n.recordRecentFileExport('/onbekend.md', 'PDF');
      expect(n.state.recentFiles, isEmpty);
    });

    test('legacy paden-lijst migreert bij laden', () async {
      SharedPreferences.setMockInitialValues({
        'recentFiles': ['/oud.md', '/ouder.md'],
      });
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.recentFiles.map((f) => f.path), ['/oud.md', '/ouder.md']);
      expect(n.state.recentFiles.first.slideCount, 0);
    });

    test(
      'recent file origins stick to their path and prune with the list',
      () async {
        final n = await _loadedNotifier();
        await n.addRecentFile('/remote.md');
        await n.setRecentFileOrigin('/remote.md', 'https://server · pad.md');

        // Herkomst blijft staan wanneer hetzelfde pad opnieuw wordt geopend
        // (lokaal her-openen maakt een remote bestand niet lokaal).
        await n.addRecentFile('/ander.md');
        await n.addRecentFile('/remote.md');
        expect(
          n.state.recentFileOrigins['/remote.md'],
          'https://server · pad.md',
        );

        // Een pad buiten de recente lijst krijgt geen herkomst.
        await n.setRecentFileOrigin('/onbekend.md', 'https://elders');
        expect(n.state.recentFileOrigins.containsKey('/onbekend.md'), isFalse);

        // Rolt het pad uit de top-10, dan verdwijnt zijn herkomst mee.
        for (var i = 0; i < 10; i++) {
          await n.addRecentFile('/deck_$i.md');
        }
        expect(n.state.recentFiles.any((f) => f.path == '/remote.md'), isFalse);
        expect(n.state.recentFileOrigins, isEmpty);
      },
    );

    // De herkomst is maar een label onder de wolk-badge, maar hij gaat
    // onversleuteld naar het prefs-domein. Een import-URL kan het
    // `gebruiker:wachtwoord@`-deel dragen dat een URL vóór de host toestaat, en
    // dan staat er een wachtwoord in gewone instellingen — precies wat
    // SecretStore voorkomt.
    group('herkomst zonder inloggegevens', () {
      test('het gebruikersdeel wordt niet bewaard', () async {
        final n = await _loadedNotifier();
        await n.addRecentFile('/remote.md');
        // Uit delen opgebouwd: een letterlijke `gebruiker:wachtwoord@host`
        // in de broncode laat de geheimenscanner terecht aanslaan.
        const user = 'bram';
        const pw = 'hunter2';
        await n.setRecentFileOrigin(
          '/remote.md',
          'https://$user:$pw@cloud.example/decks/deck.md',
        );

        final stored = n.state.recentFileOrigins['/remote.md']!;
        expect(stored, isNot(contains('hunter2')));
        expect(stored, isNot(contains('bram')));
        // Maar wél zichtbaar dát er inloggegevens in de link zaten.
        expect(stored, contains('***'));
        expect(stored, contains('cloud.example'));
      });

      test('een token in de gebruikersnaam alleen verdwijnt ook', () async {
        final n = await _loadedNotifier();
        await n.addRecentFile('/t.md');
        const token = 'ghp_geheim';
        await n.setRecentFileOrigin('/t.md', 'https://$token@git.example/x');
        expect(
          n.state.recentFileOrigins['/t.md'],
          isNot(contains('ghp_geheim')),
        );
      });

      test('een gewone URL blijft ongemoeid', () async {
        const plain = 'https://cloud.example/decks/deck.md';
        expect(SettingsNotifier.scrubbedOrigin(plain), plain);
      });

      test('een herkomst die geen URL is blijft ongemoeid', () async {
        // WebDAV en S3 schrijven `server · pad`; daar valt niets te schrobben.
        const label = 'https://server · pad.md';
        expect(SettingsNotifier.scrubbedOrigin(label), label);
        expect(
          SettingsNotifier.scrubbedOrigin('mijn-bucket · a/b.md'),
          'mijn-bucket · a/b.md',
        );
      });
    });

    test('libraries: add, rename, remove round-trip and persist', () async {
      final n = await _loadedNotifier();
      expect(n.state.libraries, isEmpty);
      expect(n.state.homeDirectory, isNull);
      expect(n.state.libraryPaths, isEmpty);

      await n.addLibrary('Privé', '/home/prive');
      await n.addLibrary('Werk', '/home/werk');
      expect(n.state.libraries.map((l) => l.name).toList(), ['Privé', 'Werk']);
      expect(n.state.libraryPaths, ['/home/prive', '/home/werk']);
      // Eerste bibliotheek geldt als standaard-startmap (compat-getter).
      expect(n.state.homeDirectory, '/home/prive');

      // Een al toegevoegd pad wordt niet nogmaals toegevoegd.
      await n.addLibrary('Privé kopie', '/home/prive');
      expect(n.state.libraries.length, 2);

      final werk = n.state.connections[1] as LocalConnection;
      await n.updateConnection(werk.copyWith(name: 'Kantoor'));
      expect(n.state.libraries[1].name, 'Kantoor');
      expect(n.state.libraries[1].path, '/home/werk');

      await n.removeConnection(n.state.connections.first.id);
      expect(n.state.libraryPaths, ['/home/werk']);

      // Persistentie: een verse notifier op dezelfde prefs leest de lijst terug.
      final reloaded = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloaded.state.libraries.map((l) => l.name).toList(), ['Kantoor']);
      expect(reloaded.state.libraryPaths, ['/home/werk']);
    });

    test('libraries: legacy homeDirectory migrates to one library', () async {
      SharedPreferences.setMockInitialValues({
        'homeDirectory': '/legacy/decks',
      });
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.libraries.length, 1);
      expect(n.state.libraries.single.path, '/legacy/decks');
      expect(n.state.homeDirectory, '/legacy/decks');
    });

    test('de oude drie sleutels worden één verbindingenlijst', () async {
      // Wie de app al gebruikte had bibliotheken, hooguit één WebDAV-bron en
      // hooguit één git-repo, elk onder een eigen prefs-sleutel. Die drie
      // moeten samen één lijst worden zonder dat er iets verschuift: de
      // bibliotheken eerst en in hun eigen volgorde, want `libraries.first` was
      // de thuismap en is nu de bovenste lokale verbinding.
      SharedPreferences.setMockInitialValues({
        'libraries': jsonEncode([
          {'name': 'Privé', 'path': '/home/prive'},
          {'name': 'Werk', 'path': '/home/werk'},
        ]),
        'webdavServer': jsonEncode({
          'baseUrl': 'https://cloud.voorbeeld.nl',
          'username': 'a.bakker',
        }),
        'gitRepo': jsonEncode({
          'baseUrl': 'https://git.voorbeeld.nl',
          'owner': 'librekat',
          'repo': 'decks',
        }),
      });
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(n.state.connections.map((c) => c.kind).toList(), [
        StorageConnectionKind.local,
        StorageConnectionKind.local,
        StorageConnectionKind.webdav,
        StorageConnectionKind.git,
      ]);
      // De afgeleide getters wijzen naar precies wat er vóór de migratie stond,
      // zodat de open- en opslaanflows niets merken.
      expect(n.state.homeDirectory, '/home/prive');
      expect(n.state.webdavServer?.username, 'a.bakker');
      expect(n.state.gitRepo?.slug, 'librekat/decks');
      // Elke verbinding krijgt een eigen, niet-lege id.
      final ids = n.state.connections.map((c) => c.id).toSet();
      expect(ids, hasLength(4));
      expect(ids.any((id) => id.isEmpty), isFalse);
    });

    test('een leeggemaakte lijst blijft leeg na herstart', () async {
      // Zonder deze regel zou de migratie opnieuw aanslaan zodra de gebruiker
      // alles verwijdert, en kwam zijn opruiming elke start terug.
      SharedPreferences.setMockInitialValues({
        'libraries': jsonEncode([
          {'name': 'Privé', 'path': '/home/prive'},
        ]),
      });
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.connections, hasLength(1));

      await n.setConnections(const []);
      final reloaded = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloaded.state.connections, isEmpty);
      expect(reloaded.state.libraries, isEmpty);
    });

    test(
      'de bovenste bruikbare verbinding van een soort is de standaard',
      () async {
        final n = await _loadedNotifier();
        const eersteServer = WebdavServer(
          baseUrl: 'https://a.voorbeeld.nl',
          username: 'a.bakker',
        );
        const tweedeServer = WebdavServer(
          baseUrl: 'https://b.voorbeeld.nl',
          username: 'a.bakker',
        );
        // Een half ingevulde verbinding telt niet mee: die staat in de lijst
        // omdat de gebruiker er nog aan werkt, niet omdat hij dienst kan doen.
        const halveServer = WebdavServer(baseUrl: '', username: '');

        await n.setConnections([
          WebdavConnection(id: 'half', name: 'In aanbouw', server: halveServer),
          WebdavConnection(id: 'a', name: 'Klant A', server: eersteServer),
          WebdavConnection(id: 'b', name: 'Klant B', server: tweedeServer),
        ]);
        expect(n.state.webdavServer?.baseUrl, 'https://a.voorbeeld.nl');

        // Herordenen is hoe de gebruiker een andere server tot standaard maakt —
        // zonder configuratie weg te gooien.
        await n.reorderConnections(2, 0);
        expect(n.state.webdavServer?.baseUrl, 'https://b.voorbeeld.nl');
        expect(n.state.connections.map((c) => c.id).toList(), [
          'b',
          'half',
          'a',
        ]);
      },
    );

    test('herordenen buiten bereik laat de lijst met rust', () async {
      final n = await _loadedNotifier();
      await n.setConnections(const [
        LocalConnection(id: 'a', name: 'A', path: '/a'),
        LocalConnection(id: 'b', name: 'B', path: '/b'),
      ]);
      await n.reorderConnections(5, 0);
      await n.reorderConnections(0, 9);
      await n.reorderConnections(1, 1);
      expect(n.state.connections.map((c) => c.id).toList(), ['a', 'b']);
    });

    test('een onleesbare verbinding sloopt de rest niet', () async {
      // Eén kapotte regel mag niet elke andere bron onbereikbaar maken.
      SharedPreferences.setMockInitialValues({
        'storageConnections': jsonEncode([
          {'id': '', 'kind': 'local', 'config': <String, Object?>{}}, // geen id
          {
            'id': 'x',
            'kind': 'zeppelin',
            'config': <String, Object?>{},
          }, // onbekende soort
          {
            'id': 'ok',
            'name': 'Werk',
            'kind': 'local',
            'config': {'path': '/home/werk'},
          },
        ]),
      });
      final n = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.connections.map((c) => c.id).toList(), ['ok']);
      expect(n.state.libraryPaths, ['/home/werk']);
    });

    test('export directory set and clear', () async {
      final n = await _loadedNotifier();
      await n.setExportDirectory('/export');
      expect(n.state.exportDirectory, '/export');

      await n.setExportDirectory(null);
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
      await notifier.setAppAppearanceProfiles([
        ...notifier.state.appAppearanceProfiles,
        AppAppearanceProfile.basic.copyWith(
          name: 'Lettertype-thema',
          fontFamily: 'Lora',
          isBuiltIn: false,
        ),
      ], selectedName: 'Lettertype-thema');
      expect(notifier.state.appAppearanceProfile.fontFamily, 'Lora');
    });
  });

  group('customChecklists (feedback #9)', () {
    test(
      'starts empty and add/update/remove persist across a reload',
      () async {
        SharedPreferences.setMockInitialValues({});
        final notifier = SettingsNotifier();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(notifier.state.customChecklists, isEmpty);

        await notifier.addCustomChecklist(
          const ChecklistTemplate(
            name: 'Interne test',
            standardLabel: 'PTES intern',
            items: [ChecklistTemplateItem(id: 'NET-01', title: 'Poortscan')],
          ),
        );
        expect(notifier.state.customChecklists, hasLength(1));

        await notifier.updateCustomChecklist(
          0,
          notifier.state.customChecklists.first.copyWith(name: 'Hernoemd'),
        );
        expect(notifier.state.customChecklists.first.name, 'Hernoemd');

        // A fresh notifier reads the persisted list back.
        final reloaded = SettingsNotifier();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(reloaded.state.customChecklists, hasLength(1));
        expect(reloaded.state.customChecklists.first.name, 'Hernoemd');
        expect(reloaded.state.customChecklists.first.items.single.id, 'NET-01');

        await notifier.removeCustomChecklist(0);
        expect(notifier.state.customChecklists, isEmpty);
      },
    );
  });

  group('Matrix account (app-global)', () {
    const account = MatrixServer(
      homeserverUrl: 'https://hs.example',
      userId: '@a:hs.example',
      deviceId: 'DEV1',
    );

    test('persists to prefs and reloads on a fresh notifier', () async {
      SharedPreferences.setMockInitialValues({});
      final first = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await first.setMatrixAccount(account);
      expect(first.state.matrixAccount, account);

      final reloaded = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloaded.state.matrixAccount, account);
    });

    test('setting null clears it (and the prefs key)', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await notifier.setMatrixAccount(account);
      await notifier.setMatrixAccount(null);
      expect(notifier.state.matrixAccount, isNull);

      final reloaded = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloaded.state.matrixAccount, isNull);
    });

    test(
      'the access token writes to and reads back from the keychain',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final notifier = SettingsNotifier(
          secretStore: SecretStore(
            storage: const FlutterSecureStorage(),
            canStore: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          await notifier.setMatrixToken(
            account.homeserverUrl,
            account.userId,
            'tok',
          ),
          isTrue,
        );
        expect(await notifier.matrixToken(account), 'tok');
        await notifier.setMatrixToken(
          account.homeserverUrl,
          account.userId,
          '',
        );
        expect(await notifier.matrixToken(account), isNull);
      },
    );

    test(
      'removing the account sweeps its collab secrets from the keychain',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final secrets = SecretStore(
          storage: const FlutterSecureStorage(),
          canStore: true,
        );
        final notifier = SettingsNotifier(secretStore: secrets);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await notifier.setMatrixAccount(account);
        // Seed some collaboration secrets for this account, as a session would.
        await secrets.writeCollabDeviceSeeds(
          account.homeserverUrl,
          account.userId,
          'seeds-blob',
        );
        await secrets.writeCollabTrust(
          account.homeserverUrl,
          account.userId,
          '{"@peer DEV":"key"}',
        );

        await notifier.setMatrixAccount(null);

        expect(
          await secrets.readCollabDeviceSeeds(
            account.homeserverUrl,
            account.userId,
          ),
          isNull,
        );
        expect(
          await secrets.readCollabTrust(account.homeserverUrl, account.userId),
          isNull,
        );
      },
    );
  });
}
