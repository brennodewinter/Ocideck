// De gebundelde stijlprofielen moeten hun eigen contrastondergrens halen (#1818).
//
// Er was niets dat dit bewaakte. Gevolg: het standaardprofiel droeg
// `checklistUncheckedColor: '#CBD5E1'` op wit — verhouding 1,48 tegen een
// drempel van 3,0 — en dus gaf élk deck met een checklist-dia meteen een
// waarschuwing die de auteur vanuit de `.md` niet kón oplossen, want styling
// staat bewust niet in het bestand (FILE_FORMAT §3.2).
//
// Deze test draait elk gebundeld profiel door dezelfde `SlideQualityAnalyzer`
// die het kwaliteitspaneel gebruikt, over een deck dat elk contrastpaar
// aanraakt dat de analyzer kent. Nul bevindingen, op één benoemde uitzondering
// na.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// De gebundelde profielen, bij naam zodat een falende test zegt wélke.
const _gebundeld = <String, ThemeProfile>{
  'Standaard': ThemeProfile(),
  'LibreKAT': ThemeProfile.libreKat,
  'Security': ThemeProfile.security,
  'Vigilis': ThemeProfile.vigilis,
};

/// Contrastbevindingen die bewust blijven staan, met de reden.
///
/// Eén regel per geval, op `<profiel>/<veld>`. Deze lijst is met opzet
/// pijnlijk expliciet: een uitzondering die je niet ziet, is een uitzondering
/// die niemand meer weghaalt. Wordt de kleur ooit aangepast, dan faalt de
/// test op de *ongebruikte* uitzondering en moet hij hier weg — dat is de
/// bedoeling.
const _aanvaard = <String, String>{
  'Vigilis/accentColor':
      'Het merkgeel #FFB800 is de merkkleur van Vigilis. Als linkkleur op wit '
      'haalt het 1,7 — onder elke drempel. Donkerder maken (naar ~#96690F, '
      '4,86) lost het op maar verandert het zichtbare merk overal: '
      'bulletmarkers, links, tabelkop, randen. Dat is een merkbesluit, geen '
      'reparatie. De keuze is bewust om het accent te laten staan; de '
      'sectiedia is wél gerepareerd in #1818 (wit op geel was onleesbaar '
      'zonder merk-afweging).',
};

/// Een deck dat elk contrastpaar aanraakt dat de analyzer kent: de titeldia
/// (titeltekst + ondertitel), de sectiedia (tussentitel + ondertitel op de
/// sectieachtergrond), een checklist (aangevinkt én niet-aangevinkt), een
/// tabel (tekst + kop) en een codeblok.
List<Slide> _dekkendDeck() => [
  const Slide(
    id: 't',
    type: SlideType.title,
    title: 'Titel',
    subtitle: 'Ondertitel',
  ),
  const Slide(
    id: 's',
    type: SlideType.section,
    title: 'Sectie',
    subtitle: 'Ondertitel',
  ),
  const Slide(
    id: 'c',
    type: SlideType.bullets,
    title: 'Checklist',
    listStyle: ListStyle.checklist,
    bullets: ['[ ] open', '[x] klaar'],
  ),
  const Slide(
    id: 'b',
    type: SlideType.table,
    tableRows: [
      ['Kop', 'Kop'],
      ['a', 'b'],
    ],
  ),
  const Slide(id: 'k', type: SlideType.code, customMarkdown: 'void main() {}'),
];

void main() {
  group('gebundelde stijlprofielen halen hun eigen contrastondergrens', () {
    for (final entry in _gebundeld.entries) {
      test('${entry.key} levert geen onverwachte contrastbevinding', () {
        final result = const SlideQualityAnalyzer().analyzeSlides(
          slides: _dekkendDeck(),
          theme: entry.value,
          font: entry.value.fontFamily,
        );

        final onverwacht = <String>[];
        for (final issue in result.issues) {
          if (issue.category != SlideQualityCategory.contrast) continue;
          // De sectiedia-toets draagt geen veld; hij meet titeltekst tegen de
          // sectieachtergrond, net zoals de stijlinstelling hem toerekent.
          final veld =
              issue.field ??
              (issue.kind == SlideQualityIssueKind.slideContrast
                  ? 'titleTextColor'
                  : issue.kind.name);
          final sleutel = '${entry.key}/$veld';
          if (_aanvaard.containsKey(sleutel)) continue;
          onverwacht.add('$sleutel ${issue.args}');
        }

        expect(
          onverwacht,
          isEmpty,
          reason:
              'een gebundeld profiel hoort niet door de ondergrens te zakken '
              'die de app zelf hanteert — pas de kleur aan, of neem hem met '
              'reden en issuenummer op in _aanvaard',
        );
      });
    }

    test('elke aanvaarde uitzondering bestaat nog echt', () {
      // Zonder deze toets blijft een uitzondering staan nadat de kleur is
      // gerepareerd, en dekt hij stilletjes de volgende fout op datzelfde veld.
      final gevonden = <String>{};
      for (final entry in _gebundeld.entries) {
        final result = const SlideQualityAnalyzer().analyzeSlides(
          slides: _dekkendDeck(),
          theme: entry.value,
          font: entry.value.fontFamily,
        );
        for (final issue in result.issues) {
          if (issue.category != SlideQualityCategory.contrast) continue;
          final veld =
              issue.field ??
              (issue.kind == SlideQualityIssueKind.slideContrast
                  ? 'titleTextColor'
                  : issue.kind.name);
          gevonden.add('${entry.key}/$veld');
        }
      }

      expect(
        _aanvaard.keys.where((k) => !gevonden.contains(k)),
        isEmpty,
        reason: 'deze uitzondering is niet meer nodig; haal hem weg',
      );
    });
  });

  test('het niet-aangevinkte vakje werkt op wit én op donker', () {
    // Waarom een midden-grijs en geen lichtere: `#CBD5E1` haalde het op wit
    // niet (1,48), en een kleur die alléén op wit werkt breekt zodra de auteur
    // zijn dia donker zet. `#64748B` is de klasse kleur die op beide uitersten
    // 3:1 haalt — 4,76 op wit, 3,90/3,75/3,07 op de donkere tinten die deze
    // repo elders gebruikt. Dat is de eigenschap die deze test vastpint, en de
    // reden dat een lichter grijs geen goede reparatie zou zijn geweest.
    //
    // Bewust alléén het niet-aangevinkte vakje. Het aangevinkte `#2E7D64`
    // haalt op `#1E293B` 2,95 — nét onder de 3,0 — maar dat is een bestaand
    // geval op een achtergrond die geen enkel gebundeld profiel voert, en het
    // repareren zou de standaard-accentkleur veranderen. Dat is een andere
    // afweging dan deze en hoort niet stilzwijgend mee te liften.
    for (final achtergrond in const [
      '#FFFFFF',
      '#111318',
      '#0F172A',
      '#1E293B',
    ]) {
      final ratio = hexContrastRatio(
        const ThemeProfile().checklistUncheckedColor,
        achtergrond,
      );
      expect(
        ratio,
        isNotNull,
        reason: 'de standaardkleur moet een geldige hex zijn',
      );
      expect(
        ratio,
        greaterThanOrEqualTo(kWcagAaLargeText),
        reason:
            'het niet-aangevinkte vakje zakt door de 3:1-ondergrens op '
            'achtergrond $achtergrond',
      );
    }
  });

  test('de standaard uit JSON is dezelfde als die uit de constructor', () {
    // `ThemeProfile.fromJson` draagt zijn eigen kopie van elke standaardwaarde.
    // Die kopie werd bij #1818 bijna vergeten: dan zou een profiel dat uit de
    // instellingen wordt geladen zónder deze sleutel alsnog het oude, te lichte
    // grijs krijgen — en precies de waarschuwing terugbrengen die hier is
    // weggehaald, bij de gebruiker die er niets aan veranderd had.
    final uitJson = ThemeProfile.fromJson(const <String, dynamic>{});

    expect(
      uitJson.checklistUncheckedColor,
      const ThemeProfile().checklistUncheckedColor,
    );
    expect(
      hexContrastRatio(
        uitJson.checklistUncheckedColor,
        uitJson.slideBackgroundColor,
      ),
      greaterThanOrEqualTo(kWcagAaLargeText),
    );
  });
}
