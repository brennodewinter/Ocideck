import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/mermaid_theme.dart';

/// De kleurmapping en directive-injectie die Mermaid-diagrammen de stijlkleuren
/// van het gekozen [ThemeProfile] laten volgen. Puur Dart — geen WebView, geen
/// Flutter-widgets — dus volledig in isolatie te toetsen.
void main() {
  group('mermaidThemeVariablesFor', () {
    test('leidt accent af als primaire kleur en tekstkleur als lijnkleur', () {
      const profile = ThemeProfile(
        name: 'Test',
        accentColor: '#2E7D64',
        textColor: '#222222',
        slideBackgroundColor: '#FFFFFF',
      );
      final vars = mermaidThemeVariablesFor(profile);
      expect(vars['primaryColor'], '#2E7D64');
      expect(vars['taskBkgColor'], '#2E7D64');
      expect(vars['lineColor'], '#222222');
      expect(vars['textColor'], '#222222');
    });

    test('geeft tekst op accent een contrastkleur', () {
      // Donker accent op lichte achtergrond: tekst op de balk wordt licht.
      const dark = ThemeProfile(
        name: 'Donker',
        accentColor: '#003399',
        slideBackgroundColor: '#FFFFFF',
      );
      final onDark = mermaidThemeVariablesFor(dark);
      expect(onDark['primaryTextColor'], '#FFFFFF');
      expect(onDark['taskTextColor'], '#FFFFFF');

      // Licht accent op lichte achtergrond: tekst op de balk wordt donker.
      const light = ThemeProfile(
        name: 'Licht',
        accentColor: '#FFFF00',
        slideBackgroundColor: '#FFFFFF',
      );
      final onLight = mermaidThemeVariablesFor(light);
      // Geel op wit heeft onvoldoende contrast; nearestContrastingHex schuift
      // naar donker tot WCAG-large (3:1) haalbaar is.
      expect(onLight['primaryTextColor']!, isNot(equals('#FFFF00')));
    });

    test('leidt severity-critical af als kritische- en vandaag-lijnkleur', () {
      const profile = ThemeProfile(
        name: 'Test',
        accentColor: '#2E7D64',
        severityCriticalColor: '#B91C1C',
      );
      final vars = mermaidThemeVariablesFor(profile);
      expect(vars['critBkgColor'], '#B91C1C');
      expect(vars['critBorderColor'], '#B91C1C');
      expect(vars['todayLineColor'], '#B91C1C');
    });

    test('leidt checklistUnchecked af als done-kleur', () {
      const profile = ThemeProfile(
        name: 'Test',
        accentColor: '#2E7D64',
        checklistUncheckedColor: '#64748B',
      );
      final vars = mermaidThemeVariablesFor(profile);
      expect(vars['doneTaskBkgColor'], '#64748B');
      expect(vars['doneTaskBorderColor'], '#64748B');
    });
  });

  group('mermaidWithThemeColors', () {
    const profile = ThemeProfile(
      name: 'Test',
      accentColor: '#2E7D64',
      textColor: '#222222',
      slideBackgroundColor: '#FFFFFF',
    );

    test('zet de themeVariables-init-directive voor de bron', () {
      final result = mermaidWithThemeColors(
        'gantt\n    dateFormat YYYY-MM-DD',
        profile,
      );
      expect(result, startsWith('%%{init: '));
      expect(result, contains('"themeVariables"'));
      expect(result, contains('"primaryColor":"#2E7D64"'));
      expect(result, contains('gantt\n    dateFormat YYYY-MM-DD'));
    });

    test('merge themeVariables in een bestaande init-directive', () {
      const src = '%%{init: {"theme":"forest"}}%%\ngraph TD; A-->B;';
      final result = mermaidWithThemeColors(src, profile);
      expect(result, startsWith('%%{init: '));
      expect(result, contains('"theme":"forest"'));
      expect(result, contains('"themeVariables"'));
      expect(result, contains('"primaryColor":"#2E7D64"'));
      expect(result, contains('graph TD; A-->B;'));
    });

    test('behoudt bestaande themeVariables en voegt profielkleuren toe', () {
      const src =
          '%%{init: {"themeVariables": {"primaryColor": "#ff0"}}}%%\ngraph TD;';
      final result = mermaidWithThemeColors(src, profile);
      // De profielkleur overschrijft de bestaande primaryColor.
      expect(result, contains('"primaryColor":"#2E7D64"'));
      expect(result, contains('"taskBkgColor":"#2E7D64"'));
      expect(result, contains('graph TD;'));
    });

    test('plaatst de directive na YAML-frontmatter', () {
      const src = '---\ntitle: Flow\n---\ngraph TD; A-->B;';
      final result = mermaidWithThemeColors(src, profile);
      expect(result, startsWith('---\ntitle: Flow\n---\n%%{init: '));
      expect(result, contains('graph TD; A-->B;'));
    });

    test(
      'verschillende profielen geven verschillende bron (cache-sleutel)',
      () {
        const a = ThemeProfile(name: 'A', accentColor: '#2E7D64');
        const b = ThemeProfile(name: 'B', accentColor: '#003399');
        const src = 'graph TD; A-->B;';
        expect(
          mermaidWithThemeColors(src, a),
          isNot(equals(mermaidWithThemeColors(src, b))),
        );
      },
    );
  });

  group('injectIntoMermaidInit', () {
    test('voegt overrides toe aan de JSON van een bestaande directive', () {
      const src = '%%{init: {"theme":"forest"}}%%\ngraph TD;';
      final result = injectIntoMermaidInit(src, {'theme': 'dark'});
      expect(result, '%%{init: {"theme":"dark"}}%%\ngraph TD;');
    });

    test('behoudt bestaande sleutels die niet in overrides staan', () {
      const src =
          '%%{init: {"theme":"forest","maxTextSize":50000}}%%\ngraph TD;';
      final result = injectIntoMermaidInit(src, {'theme': 'dark'});
      final config =
          jsonDecode(result!.split('%%{init: ')[1].split('}%%')[0])
              as Map<String, dynamic>;
      expect(config['theme'], 'dark');
      expect(config['maxTextSize'], 50000);
    });

    test('geeft null bij afwezige directive', () {
      expect(
        injectIntoMermaidInit('graph TD; A-->B;', {'theme': 'dark'}),
        null,
      );
    });

    test('geeft null bij ongeldig JSON in de directive', () {
      const src = '%%{init: {not valid json}%%\ngraph TD;';
      expect(injectIntoMermaidInit(src, {'theme': 'dark'}), null);
    });
  });
}
