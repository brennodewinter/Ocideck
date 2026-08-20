import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_front_matter_codec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/presentation/audience_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een stijlprofiel draagt meerregelige Markdown: de slotdia, en de kop- en
/// voettekst van een document. Elke schakel die zo'n waarde opslaat of
/// doorgeeft ontsnapt de regelovergang, en moet hem er even hard weer uit
/// halen. Ontsnapt één schakel wél en herstelt niemand, dan groeit `\n` per
/// ronde met een backslash: eerst `\n` als twee tekens, dan `\\n` als drie. De
/// gebruiker ziet het pas in de PDF- en HTML-export, waar op elke bladzijde een
/// letterlijke `\n` in de kop staat.
///
/// Deze test pint de hele keten vast op één belofte: wat erin gaat komt eruit,
/// en in de opgeslagen tekst staat nooit een ontsnapte backslash.
///
/// De aanleiding was een profiel in de prefs waar `# Bedankt\n\nVragen?` als
/// `# Bedankt\\n\\nVragen?` stond. De schuldige bleek buiten de app te liggen —
/// `defaults read` drukt een string in OpenStep-notatie af en verdubbelt daarbij
/// elke backslash, en een hulpscript schreef die uitvoer zonder herstel terug.
/// De keten zelf was schoon; deze test houdt dat zo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Drie velden met een echte regelovergang, waaronder twee met een sluitende
  /// newline: die valt in regelgebaseerde formaten het eerst om, en verdwijnt
  /// stil in elke `trim()` onderweg.
  const multiline = ThemeProfile(
    name: 'Meerregelig',
    closingSlideMarkdown: '# Bedankt\n\nVragen?',
    documentHeaderText: '**VERTROUWELIJK**\n',
    documentFooterText: '**Vigilis Consultancy**\n',
  );

  void expectIntact(ThemeProfile profile, String schakel) {
    expect(
      profile.closingSlideMarkdown,
      multiline.closingSlideMarkdown,
      reason: '$schakel verminkt closingSlideMarkdown',
    );
    expect(
      profile.documentHeaderText,
      multiline.documentHeaderText,
      reason: '$schakel verminkt documentHeaderText',
    );
    expect(
      profile.documentFooterText,
      multiline.documentFooterText,
      reason: '$schakel verminkt documentFooterText',
    );
  }

  /// In de opgeslagen tekst hoort een regelovergang als JSON-ontsnapping `\n`
  /// te staan. Staat er `\\n`, dan heeft iemand een al ontsnapte waarde nóg
  /// eens ontsnapt — precies de fout die deze test moet vangen, en die je aan
  /// de heen-en-terugweg alleen niet ziet wanneer beide kanten hem maken.
  void expectNoDoubleEscape(String stored, String schakel) {
    expect(
      stored,
      isNot(contains(r'\\')),
      reason: '$schakel schrijft een ontsnapte backslash weg',
    );
  }

  test('de prefs-ronde laat de regelovergangen staan', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SettingsNotifier();
    // De constructor start een asynchrone laadronde; die eerst laten landen.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await notifier.saveThemeProfile(multiline, previousName: '');

    final prefs = await SharedPreferences.getInstance();
    expectNoDoubleEscape(prefs.getString('themeProfiles')!, 'prefs');
    expectNoDoubleEscape(prefs.getString('themeProfile')!, 'prefs');

    // Een verse notifier op dezelfde prefs is wat een herstart van de app doet.
    final herstart = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expectIntact(
      herstart.state.themeProfiles.firstWhere((p) => p.name == multiline.name),
      'prefs',
    );
  });

  test('de envelop naar het publieksvenster laat de regelovergangen staan', () {
    // Spiegelt de twee kanten van de beamer-overdracht: de presentator codeert
    // het profiel naast de markdown (`_audienceWindowArguments`), en main.dart
    // decodeert de envelop voordat AudienceWindow er `fromJson` op doet.
    final envelop = jsonEncode({beamerStyleProfileKey: multiline.toJson()});
    expectNoDoubleEscape(envelop, 'beamer-envelop');

    final args = Map<String, dynamic>.from(jsonDecode(envelop) as Map);
    expectIntact(
      ThemeProfile.fromJson(
        Map<String, Object?>.from(args[beamerStyleProfileKey] as Map),
      ),
      'beamer-envelop',
    );
  });

  test('een .ocideckstyle-bestand laat de regelovergangen staan', () async {
    final file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final built = await file.buildStyleProfileBytes(multiline);
    expectNoDoubleEscape(utf8.decode(built.bytes), 'ocideckstyle');

    final outcome = await file.importStyleProfileBytes(built.bytes);
    expectIntact(outcome.profile!, 'ocideckstyle');
  });

  test('markdownYamlScalar en zijn parser zijn elkaars omgekeerde', () {
    // De enige ontsnapper in de keten die een regelovergang écht opvouwt. Zou
    // hier ooit een kant bijkomen die de andere niet kent, dan begint het
    // aangroeien van backslashes hier.
    for (final value in const [
      '# Bedankt\n\nVragen?',
      '**VERTROUWELIJK**\n',
      r'Een pad C:\map en een "citaat"',
      'tab\ther\reind',
    ]) {
      expect(
        parseMarkdownYamlScalar(markdownYamlScalar(value)),
        value,
        reason: 'de YAML-scalar-ronde verminkt ${jsonEncode(value)}',
      );
    }
  });
}
