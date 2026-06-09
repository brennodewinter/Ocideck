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
}
