// Wat de PDF-export van een document nodig heeft uit de schil: de vertaalde
// teksten en de zin die de gebruiker te zien krijgt als er iets níet gezet kon worden.
//
// Staat los van `document_editor_screen.dart`, zodat de editor en zijn
// exportlogica de vertaalde labels en meldingen kunnen delen.

import '../../l10n/app_localizations.dart';
import '../../services/mermaid_render_service.dart';
import '../../services/pdf/document_pdf_export.dart';

export '../../services/pdf/pdf_fallback_fonts.dart' show loadPdfFallbackFonts;

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
