// Wat de PDF-export van een document nodig heeft uit de schil: de gebundelde
// lettersnede voor tekens buiten Latin-1, de vertaalde teksten, en de zin die de
// gebruiker te zien krijgt als er iets níet gezet kon worden.
//
// Staat los van `document_editor_screen.dart` omdat de PDF-lagen bewust
// Flutter-vrij zijn (zie `lib/services/pdf/`): het laden van een asset en het
// opzoeken van een vertaling zijn juist wél schilwerk, en horen dus hier.

import 'package:material_ui/material_ui.dart'
    show ScaffoldMessengerState, SnackBar, Text;
import 'package:flutter/services.dart' show ByteData, rootBundle;

import '../../l10n/app_localizations.dart';
import '../../services/mermaid_render_service.dart';
import '../../services/pdf/document_pdf_export.dart';

/// Het gebundelde lettertype waar tekens buiten Latin-1 op terugvallen.
///
/// De PDF zelf wordt gezet met de veertien standaardsneden die elke lezer heeft
/// — die dragen een echte vette en cursieve snede en kosten geen bytes, maar ze
/// reiken niet verder dan Latin-1. Roboto vangt de rest op: Latijns uitgebreid,
/// Grieks, Cyrillisch. Zie de kop van `document_pdf_fonts.dart`.
///
/// Lukt het laden niet, dan gaat de export gewoon door: [DocumentPdfResult]
/// De terugvalfonts voor de PDF-export, in de volgorde waarin ze geprobeerd
/// worden.
///
/// De export zet de lopende tekst met de veertien standaardsneden van PDF —
/// die dragen een echte vette en cursieve snede en kosten geen bytes, maar ze
/// reiken niet verder dan Latin-1. Deze lijst vangt de rest op. Zie de kop van
/// `document_pdf_fonts.dart`.
///
/// De volgorde is de bedoeling, niet toeval:
///
///  1. **Roboto** — Latijns uitgebreid, Grieks, Cyrillisch. Ook de
///     interfaceletter, dus de PDF lijkt op wat de auteur zag.
///  2. **Inter** — pijlen (`→ ← ↔ ⇒`), vinkjes (`✓ ✗`) en vormen (`★ ▪`) die
///     Roboto níét dekt, mét alle letters erbij. Zat al in de app als
///     interfaceletter, dus dit kost geen byte extra (#1987).
///  3. **Noto Sans Math** — de diepere wiskunde (`∮ ⨁`) die de andere twee niet
///     hebben. Een subset, beperkt tot de blokken die in diagrammen en formules
///     voorkomen — ~250 KB in plaats van de volledige 1 MB (#1968).
///
/// Waarom Inter vóór het wiskundefont staat: een ingesloten tekening krijgt
/// *één* snede voor al haar tekst, want de SVG-lezer ketent niet. Een font met
/// pijlen maar zonder letters is daar de verkeerde keuze — en zonder spatie
/// zelfs een afbreker (#1987).
///
/// Lukt het laden van een font niet, dan gaat de export gewoon door met wat er
/// wél is: [DocumentPdfResult] meldt dan welke tekens ontbreken, en de schil
/// zegt dat tegen de gebruiker.
Future<List<ByteData>> loadPdfFallbackFonts() async {
  const paths = [
    'assets/fonts/Roboto-Variable.ttf',
    'assets/fonts/Inter-Variable.ttf',
    'assets/fonts/NotoSansMath-subset.ttf',
  ];
  final fonts = <ByteData>[];
  for (final path in paths) {
    try {
      fonts.add(await rootBundle.load(path));
    } on Exception {
      // Eén font dat niet laadt mag de export niet kosten; de melding over
      // ontbrekende tekens vertelt de gebruiker vanzelf wat er dan mist.
      continue;
    }
  }
  return fonts;
}

/// De teksten die de PDF-lagen zelf niet kennen, in de taal van de interface.
DocumentPdfLabels documentPdfLabels(AppLocalizations l10n) => DocumentPdfLabels(
  footnotesTitle: l10n.d('Noten'),
  // Eerlijk benoemen wat er staat: niet het diagram maar de bron ervan. Een
  // PDF kent geen JavaScript, dus wat de HTML-export tekent kan hier alleen
  // leesbaar mee — zie [PdfVerbatimBlock].
  mathLabel: l10n.d('Formule (bron)'),
  mermaidLabel: l10n.d('Diagram (bron)'),
  chartLabel: l10n.d('Grafiek (bron)'),
);

/// De melding bij tekens waarvoor geen enkele beschikbare snede een vorm had.
///
/// Noemt de tekens zelf, want "sommige tekens" laat de gebruiker zoeken in zijn
/// eigen document. Bij veel verschillende tekens wordt de lijst afgekapt — de
/// boodschap is dán al aangekomen.
String unsupportedCharactersMessage(AppLocalizations l10n, Set<int> runes) {
  const maxShown = 12;
  final shown = runes.take(maxShown).map(String.fromCharCode).join(' ');
  final suffix = runes.length > maxShown ? ' …' : '';
  return '${l10n.d('Deze tekens konden niet in de PDF worden gezet en ontbreken erin:')} '
      '$shown$suffix. '
      '${l10n.d('Exporteer naar HTML of LaTeX als ze in het document horen.')}';
}

/// De melding bij een tabel die ook op de kleinste letter niet op het blad past.
///
/// Noemt wát er misgaat en niet alleen dát het misgaat: bij een hash of een
/// IP-adres is een afbreking midden in de waarde geen schoonheidsfout maar
/// verlies — de lezer kan hem daarna niet meer overnemen of vergelijken. Het
/// advies noemt de twee vormen die wél passen, want "maak de tabel smaller" is
/// geen handeling die iemand kan uitvoeren.
String tablesTooWideMessage(AppLocalizations l10n, int count) {
  final wat = count == 1
      ? l10n.d(
          'Eén tabel past niet op de bladbreedte, ook niet op de kleinste letter.',
        )
      : l10n
            .d(
              '{n} tabellen passen niet op de bladbreedte, ook niet op de kleinste letter.',
            )
            .replaceAll('{n}', '$count');
  return '$wat '
      '${l10n.d('Lange woorden en waarden zoals hashes of IP-adressen zijn daardoor middenin afgebroken.')} '
      '${l10n.d('Splits de tabel, of zet lange waarden onder elkaar in plaats van naast elkaar.')}';
}

/// Meld dat de PDF is geschreven met een tabel die niet paste.
///
/// Een waarschuwing en geen fout: het bestand staat er, en de tabel is te lezen
/// — alleen de lange waarden erin niet meer betrouwbaar over te nemen.
void warnAboutTablesTooWide(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int count,
) => messenger.showSnackBar(
  SnackBar(
    content: Text(tablesTooWideMessage(l10n, count)),
    duration: const Duration(seconds: 8),
  ),
);

/// Meld dat de PDF is geschreven maar tekens mist.
///
/// Het bestand staat er wél — daarom een waarschuwing en geen fout. Wat níet mag
/// gebeuren is dat de gebruiker het zelf moet ontdekken: een teken dat geen
/// enkele snede kent verdwijnt uit de tekstlaag, en dus ook uit zoeken,
/// kopiëren en de voorleessoftware.
///
/// Neemt de messenger en niet een `BuildContext`: de aanroeper pakt hem vóór het
/// wachten op de export vast, want daarna is de context niet meer te vertrouwen
/// en zou de waarschuwing stil wegvallen.
void warnAboutUnsupportedCharacters(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Set<int> runes,
) => messenger.showSnackBar(
  SnackBar(
    content: Text(unsupportedCharactersMessage(l10n, runes)),
    duration: const Duration(seconds: 8),
  ),
);

/// De melding bij een logo dat te grof is voor drukwerk.
///
/// Noemt de maten, want zonder die twee getallen is "te grof" een oordeel waar
/// niemand iets mee kan. Mét die getallen weet de gebruiker precies wat er van
/// het bronbestand wordt gevraagd.
String coarseLogoMessage(AppLocalizations l10n, LogoResolution logo) {
  final measured = l10n
      .d(
        'Het logo komt korrelig uit de printer: het bestand is {breed}×{hoog} px en komt op deze maat uit op {dpi} dpi.',
      )
      .replaceAll('{breed}', '${logo.pixelWidth}')
      .replaceAll('{hoog}', '${logo.pixelHeight}')
      .replaceAll('{dpi}', '${logo.dpi.round()}');
  final advice = l10n
      .d(
        'Kies een logo van minstens {px} px breed, of zet de logomaat kleiner.',
      )
      .replaceAll('{px}', '${logo.advisedPixelWidth}');
  return '$measured $advice';
}

/// Meld dat de PDF is geschreven met een logo dat te grof is voor drukwerk.
///
/// Een waarschuwing en geen fout: het bestand staat er, en op het scherm valt
/// het meestal niet op. Op papier wel — en dat merkt de gebruiker anders pas na
/// het drukken.
void warnAboutCoarseLogo(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  LogoResolution logo,
) => messenger.showSnackBar(
  SnackBar(
    content: Text(coarseLogoMessage(l10n, logo)),
    duration: const Duration(seconds: 8),
  ),
);

/// Hoe lang de export hoogstens op één tekening wacht.
///
/// Ruim genoeg voor een zwaar diagram op een trage machine, en kort genoeg dat
/// een document met tien diagrammen niet een halve dag kan duren.
const _graphicBudget = Duration(seconds: 20);

/// Wacht hoogstens [limit] op een tekening, en levert anders niets.
///
/// De renderer heeft zelf al een plafond, maar dat helpt niet tegen het geval
/// dat er hier werkelijk toe doet: een verzoek dat de wachtrij nooit verlaat
/// omdat de verborgen WebView niet gemonteerd is. Zonder dít plafond hangt de
/// export dan op één diagram — en een export die blijft hangen is erger dan een
/// diagram dat als bron in het bestand komt.
Future<String?> graphicWithinBudget(
  Future<String?> render, {
  Duration limit = _graphicBudget,
}) => render.timeout(limit, onTimeout: () => null);

/// Het mermaid-diagram voor de PDF, als SVG.
Future<String?> renderMermaidForPdf(String source) =>
    graphicWithinBudget(MermaidRenderService.instance.render(source));

/// De formule voor de PDF, als SVG. Op web niet beschikbaar; dan valt de
/// formule terug op haar bron.
Future<String?> renderMathForPdf(String tex) =>
    graphicWithinBudget(MermaidRenderService.instance.renderMath(tex));
