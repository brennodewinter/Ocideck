import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Een dia beweegt niet mee met het app-thema.
///
/// Een dia is een vast wit canvas: hij rendert in de preview, op de beamer en in
/// een headless export-isolate identiek. De export schrijft altijd de lichte
/// waarden. Een dia-onderdeel dat zich uit een **mode-afhankelijk**
/// `AppTheme`-token kleurt breekt dat op twee manieren tegelijk — het keert om in
/// donkere modus (de tooltip werd wit-op-wit, 1,18:1; het codeblok donker-op-
/// donker, 1,23:1) én het wijkt af van de export, terwijl het exportdialoog
/// belooft dat preview en export gelijk zijn (#822).
///
/// `app_theme_contrast_test.dart` heeft hier al een toets voor, maar die somt
/// drie tokens op (`slideInk`, `slideInkMuted`, `slideInkSoft`). Een tokenlijst
/// bewaakt wat erin staat — en `ink`, `ghSurface`, `ghInk`, `ghBorder` en
/// `warningFg` stonden er niet in. Deze toets draait het om: hij leest de
/// mode-afhankelijke tokens uit `app_theme.dart` zélf (elke `get X => _m(…)`) en
/// controleert dat géén ervan in het dia-renderpad voorkomt. Zo veroudert hij
/// niet bij het volgende token dat mode-afhankelijk wordt gemaakt.
void main() {
  test('geen mode-afhankelijk AppTheme-token in het dia-renderpad', () {
    // De mode-afhankelijke tokens: de getters die door `_m(licht, donker)` gaan.
    final source = File('lib/theme/app_theme.dart').readAsStringSync();
    final modeAware = RegExp(
      r'static Color get (\w+) =>\s*\n?\s*_m\(',
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(
      modeAware,
      isNotEmpty,
      reason: 'de mode-afhankelijke getters horen gevonden te worden',
    );
    final alternation = modeAware.map(RegExp.escape).join('|');
    final tokenRef = RegExp('\\bAppTheme\\.($alternation)\\b');

    // Het dia-renderpad: de per-type preview-widgets en het mermaid-diagram.
    // Dít gaat de export in. De chrome eromheen (dialogen, popovers, de
    // thumbnail-badges) mag wél mode-afhankelijk zijn — die staat niet op de
    // dia, en hoort juist met het thema mee te bewegen.
    final renderPath = <File>[
      ...Directory(
        'lib/widgets/slides/previews',
      ).listSync(recursive: true).whereType<File>(),
      File('lib/widgets/slides/mermaid_diagram.dart'),
    ].where((f) => f.path.endsWith('.dart'));

    final overtreders = <String>[];
    for (final file in renderPath) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in tokenRef.allMatches(lines[i])) {
          overtreders.add(
            '${file.path.replaceAll(r'\', '/')}:${i + 1}  ${m.group(1)}',
          );
        }
      }
    }

    expect(
      overtreders,
      isEmpty,
      reason:
          'Deze plekken schilderen dia-inhoud met een token dat met het thema '
          'meebeweegt. Op een dia moet de kleur vast zijn (een `const` token of '
          'een vaste kant), anders wijkt de donkere-modus-preview af van de '
          'lichte export en keert het contrast om:\n${overtreders.join('\n')}',
    );
  });
}
