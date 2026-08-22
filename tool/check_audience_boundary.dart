// De privacy-projectiegrens (docs/design/OCIWACHT.md §6), generiek bewaakt.
//
// SECURITY_DESIGN §8 belooft een compile-time garantie: dia-inhoud bereikt een
// ontvanger alleen als `AudienceDeck`, en dat type is alleen via
// `PrivacyProjection` te maken. De compiler houdt die belofte — maar alleen
// voor de functies die het type ook echt eisen. De vraag die daaronder ligt is
// *welke* functies dat zijn, en die stond hier als een lijst van vier
// hard-gecodeerde instappunten. Een vijfde uitvoeroppervlak werd niet gezien;
// precies het faalpad dat §6.0 "fail-open" noemt.
//
// De voor de hand liggende omkering — verdenk elke functie die een rauwe `Deck`
// aanneemt — levert ruis: 208 zulke parameters over 67 bestanden. Dat is geen
// signaal, dat is een lijst die niemand leest.
//
// Wat wél werkt is sleutelen op UITVOER. Een functie die dia-inhoud aanneemt
// *en* in zijn eigen body een artefact-primitief raakt, maakt iets wat de map
// van de gebruiker verlaat. Dat zijn er een handvol, en elk daarvan is een
// bewuste keuze waard.
//
// Maar — en dit is de kern — de keuze zelf valt niet statisch af te leiden.
// Een `.ocideck`-pakket draagt de BRON, één op één, en redigeren zou daar juist
// fout zijn: §6.0 zegt letterlijk dat het deck 1-op-1 naar de `.md` gaat. Een
// PDF-export draagt een projectie, en een rauwe `Deck` zou daar een lek zijn.
// Dezelfde vorm, tegengestelde eis. Geen enkele regel leidt dat verschil af.
//
// Daarom classificeert deze poort niet, maar dwingt hij een classificatie AF:
// elk gevonden oppervlak moet in [_registry] staan, met een soort en een reden.
// Een nieuw uitvoerkanaal breekt de bouw tot iemand opschrijft aan welke kant
// het staat. Dat is de winst tegenover vier vaste namen — niet dat de poort het
// antwoord weet, maar dat hij de vraag niet meer laat overslaan.
//
// Wat deze poort NIET ziet: een oppervlak dat het schrijven aan een hulpfunctie
// twee lagen verderop overlaat en zelf alleen strings doorgeeft. De analyse
// kijkt binnen één declaratie, niet door de aanroepgraaf heen. De laag die het
// primitief uiteindelijk aanraakt wordt wél gezien, zolang die de dia-inhoud
// nog in handen heeft.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Aan welke kant van de projectiegrens een oppervlak staat.
enum SurfaceKind {
  /// Levert dia-inhoud aan een ONTVANGER. Moet een `AudienceDeck` of
  /// `ExportBundle` eisen; een rauwe `Deck` is hier een lek.
  audience,

  /// Schrijft de BRON terug voor de gebruiker zelf, één op één. Redigeren zou
  /// hier juist fout zijn — dan levert een export van je eigen werk je eigen
  /// werk niet meer op.
  source,
}

class Surface {
  const Surface(this.kind, this.reason);

  final SurfaceKind kind;

  /// Waarom dit oppervlak aan die kant staat. Verplicht, en niet als
  /// formaliteit: dit is het enige wat de volgende lezer ervan weerhoudt de
  /// classificatie voor willekeurig aan te zien.
  final String reason;
}

/// Elk oppervlak dat dia-inhoud met een artefact-primitief verbindt.
///
/// Sleutel = `pad::functienaam`. Staat er iets in dat niet meer bestaat, dan
/// faalt deze poort ook — een verouderde registratie wekt de indruk dat er iets
/// bewaakt wordt.
const Map<String, Surface> _registry = {
  // ── Naar een ontvanger: projectie verplicht ──────────────────────────────
  'lib/services/slide_rasterizer.dart::rasterize': Surface(
    SurfaceKind.audience,
    'Rastert dia\'s naar PNG voor PDF en PPTX — wat hier in gaat, ziet de '
    'ontvanger letterlijk.',
  ),
  'lib/services/export_service.dart::export': Surface(
    SurfaceKind.audience,
    'De servicepoort onder elk exportformaat. Nam ooit losse `String? '
    'markdown` en `List<String>? notes`, waardoor een nieuwe aanroeper '
    'ongeprojecteerde tekst kon binnendragen; sinds die één ExportBundle '
    'zijn, houdt de grens.',
  ),
  'lib/widgets/presentation/fullscreen_presenter.dart::present': Surface(
    SurfaceKind.audience,
    'Het publieksvenster. Een zaal is een ontvanger, ook al komt er geen '
    'bestand aan te pas.',
  ),
  'lib/widgets/presentation/session_export.dart::_downloadSessionSlides': Surface(
    SurfaceKind.audience,
    'Session-data-export (#1235): per gewijzigde dia één .md naar de spreker. '
    'De data verlaat het deck naar losse bestanden die elders gebruikt worden — '
    'een ontvanger-oppervlak. Gaat door PrivacyProjection.forAudience, met een '
    'waarschuwingsschildje als de scan persoonsgegevens vindt.',
  ),
  'lib/widgets/dialogs/export_dialog.dart::show': Surface(
    SurfaceKind.audience,
    'Krijgt een fabriek die per doelgroepprofiel een bundel oplevert, zodat de '
    'bron er ook hier niet in komt.',
  ),
  'lib/services/document_export_service.dart::writeDocumentExport': Surface(
    SurfaceKind.audience,
    'De documentmodus-export (§11.2): schrijft het geprojecteerde `.md`, HTML, '
    'LaTeX of PDF weg — op desktop atomisch naar schijf, op web als '
    'browser-download via FilePicker.saveFile. De geredigeerde body komt via '
    'de ExportBundle binnen (projectedDocumentBody leest '
    'bundle.audience.deck), nooit de rauwe bron; daarom neemt de '
    'schrijfsignatuur een ExportBundle en geen rauwe Deck. Het `.md` krijgt '
    'daarnaast de geldende paginaopmaak als frontmatter mee (#1536): papiermaat, '
    'marges en afloop in millimeters. Dat is de enige inhoud die niet door de '
    'projectie komt, en het kán er ook niet doorheen — het zijn afmetingen uit '
    'de instellingen, geen tekst uit het document. De PDF-tak zet een echte '
    'tekstlaag (te selecteren, te doorzoeken); de fail-closed test meet op de '
    'geleverde bytes (test/pdf/document_pdf_export_privacy_test.dart).',
  ),

  // ── De bron terug naar de gebruiker: redigeren zou hier fout zijn ────────
  //
  // Deze stonden nergens geclassificeerd, en dat was de eigenlijke leemte. Het
  // is geen lek — het pakket hoort de bron te dragen — maar wie hierna een
  // export toevoegt, kon nergens zien aan welke kant hij stond.
  'lib/services/file/file_service_package.dart::exportPackage': Surface(
    SurfaceKind.source,
    'Een `.ocideck`-pakket is het project zelf: de `.md` plus de assets, zodat '
    'de gebruiker zijn werk kan meenemen. OCIWACHT §6.0 zegt met zoveel '
    'woorden dat het deck 1-op-1 naar de `.md` gaat. Redigeren zou hier de '
    'uitgang blokkeren die het hele formaat rechtvaardigt.',
  ),
  'lib/services/openkat/openkat_import_service.dart::_writeSidecars': Surface(
    SurfaceKind.source,
    'Schrijft het importmanifest en de per-organisatie-JSON naast het deck in '
    'data/openkat/ — de eigen brondata van de gebruiker, op zijn eigen '
    'machine, zodat de import controleerbaar en herhaalbaar is (#767). Er '
    'vertrekt hier niets naar een ontvanger; wat wél de deur uit gaat loopt '
    'via de export-oppervlakken hierboven, mét projectie.',
  ),
  'lib/services/openkat/openkat_import_service.dart::_writeDeck': Surface(
    SurfaceKind.source,
    'Schrijft het gegenereerde deck als .md naar processed-data/ (volledig) '
    'en presentations/ (ingekort) op de eigen machine. Beide zijn '
    'bronbestanden voor de gebruiker; wat de deur uit gaat loopt via de '
    'export-oppervlakken, mét projectie.',
  ),
  'lib/services/file/file_service_package.dart::downloadPackage': Surface(
    SurfaceKind.source,
    'Dezelfde bytes als exportPackage, via de bestandskiezer in plaats van een '
    'pad.',
  ),
  'lib/services/file/file_service_dossier.dart::exportDossier': Surface(
    SurfaceKind.source,
    'Het auditdossier is het pakket plus een index en een eventueel gerenderd '
    'rapport, versleuteld. Het is bewijsmateriaal voor een auditor: '
    'volledigheid is de bedoeling, en een geredigeerd dossier bewijst '
    'niets. Het gerenderde rapport erin komt wél uit de projectie.',
  ),
  'lib/services/file/file_service_dossier.dart::downloadDossier': Surface(
    SurfaceKind.source,
    'Dezelfde bytes als exportDossier, via de bestandskiezer.',
  ),
  'lib/services/file/file_service_open.dart::_writeSidecar': Surface(
    SurfaceKind.source,
    'De inkt-sidecar naast het deck van de gebruiker zelf.',
  ),
  'lib/services/file/file_service_open.dart::_writeUserNotesSidecar': Surface(
    SurfaceKind.source,
    'De notitie-sidecar naast het deck van de gebruiker zelf.',
  ),
  'lib/services/file/file_service_open.dart::_writeMiauwSidecar': Surface(
    SurfaceKind.source,
    'De MIAUW-sidecar naast het deck van de gebruiker zelf.',
  ),
  'lib/services/file/file_service_open.dart::_writeSealSidecar': Surface(
    SurfaceKind.source,
    'De zegel-sidecar naast het deck van de gebruiker zelf.',
  ),
  'lib/services/file/file_service_open.dart::_writeChartData': Surface(
    SurfaceKind.source,
    'Grafiekdata terug naar `data/*.json` in het project van de gebruiker.',
  ),
  'lib/services/file/file_service_open.dart::_copyChartData': Surface(
    SurfaceKind.source,
    'Kopieert een grafiekdatabestand mee binnen het project.',
  ),
  'lib/services/file/file_service_project.dart::_writeProject': Surface(
    SurfaceKind.source,
    'Het projectbestand van de gebruiker zelf.',
  ),
  'lib/widgets/dialogs/seal_timestamp_dialog.dart::_exportTsq': Surface(
    SurfaceKind.source,
    'Schrijft een RFC 3161-tijdstempelverzoek weg: een hash plus een nonce, '
    'geen dia-inhoud. Het deck staat alleen in de parameterlijst omdat de '
    'hash eruit berekend wordt.',
  ),
};

/// De primitieven waarmee een artefact de map van de gebruiker verlaat, of
/// waarmee dia-inhoud een ontvangend kanaal bereikt.
const _artifactPrimitives = [
  'FilePicker.saveFile(',
  'Clipboard.setData(',
  '.toImage(',
  '.toByteData(',
  'writeBytesAtomic(',
  'writeStringAtomic(',
];

final _rawDeckParam = RegExp(r'\b(Deck|List<Slide>)\b');
final _projectedParam = RegExp(r'\b(AudienceDeck|ExportBundle)\b');

class _SurfaceScanner extends RecursiveAstVisitor<void> {
  _SurfaceScanner(this.path, this.source);

  final String path;
  final String source;

  /// `pad::naam` van elke declaratie die dia-inhoud aan een artefact koppelt.
  final found = <String>{};

  /// De parameterlijst per gevonden declaratie, voor de signatuurtoets.
  final params = <String, String>{};

  void _check(String name, FormalParameterList? parameters, AstNode? body) {
    if (parameters == null || body == null) return;
    final p = parameters.toSource();
    if (!_rawDeckParam.hasMatch(p) && !_projectedParam.hasMatch(p)) return;
    final b = source.substring(body.offset, body.end);
    if (!_artifactPrimitives.any(b.contains)) return;
    final key = '$path::$name';
    found.add(key);
    params[key] = p;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _check(node.name.lexeme, node.parameters, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final fn = node.functionExpression;
    _check(node.name.lexeme, fn.parameters, fn.body);
    super.visitFunctionDeclaration(node);
  }
}

/// De parameterlijst van [entry] in [source], of null als hij er niet staat.
/// Gebruikt voor de geregistreerde audience-oppervlakken, die de scanner niet
/// vindt zodra ze al een `AudienceDeck` eisen zónder artefact-primitief in hun
/// eigen body (het schrijven zit dan een laag dieper).
String? _paramListOf(String source, String entry) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final finder = _DeclarationFinder(entry);
  unit.accept(finder);
  return finder.parameters;
}

class _DeclarationFinder extends RecursiveAstVisitor<void> {
  _DeclarationFinder(this.wanted);

  final String wanted;
  String? parameters;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == wanted) {
      parameters ??= node.parameters?.toSource();
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme == wanted) {
      parameters ??= node.functionExpression.parameters?.toSource();
    }
    super.visitFunctionDeclaration(node);
  }
}

Iterable<File> _dartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    // Vertaaldata draagt geen dia-inhoud en is enorm.
    if (e.path.replaceAll(r'\', '/').contains('lib/l10n/')) continue;
    yield e;
  }
}

void main() {
  final problems = <String>[];
  final discovered = <String, String>{};

  for (final file in _dartFiles()) {
    final path = file.path.replaceAll(r'\', '/');
    final source = file.readAsStringSync();
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final scanner = _SurfaceScanner(path, source);
    unit.accept(scanner);
    for (final key in scanner.found) {
      discovered[key] = scanner.params[key]!;
    }
  }

  // 1. Alles wat gevonden is, moet geclassificeerd zijn.
  for (final entry in discovered.entries) {
    if (_registry.containsKey(entry.key)) continue;
    problems.add(
      '${entry.key}: koppelt dia-inhoud aan een artefact-primitief maar staat '
      'niet in _registry. Bepaal aan welke kant van de projectiegrens dit '
      'staat — levert het aan een ONTVANGER (dan een AudienceDeck of '
      'ExportBundle eisen, soort `audience`), of schrijft het de BRON terug '
      'voor de gebruiker zelf (soort `source`)? Zet het erbij, mét de reden.',
    );
  }

  // 2. Elke registratie moet nog bestaan, en aan zijn eigen eis voldoen.
  _registry.forEach((key, surface) {
    final parts = key.split('::');
    final file = File(parts[0]);
    if (!file.existsSync()) {
      problems.add('$key: bestand bestaat niet meer — werk _registry bij');
      return;
    }
    if (surface.reason.trim().isEmpty) {
      problems.add('$key: geregistreerd zonder reden');
    }
    final params = _paramListOf(file.readAsStringSync(), parts[1]);
    if (params == null) {
      problems.add('$key: declaratie niet gevonden — werk _registry bij');
      return;
    }
    if (surface.kind != SurfaceKind.audience) return;
    // `ExportBundle` telt ook: die is niet te maken zonder een AudienceDeck
    // (zie zijn constructor), dus de grens houdt transitief stand.
    if (!_projectedParam.hasMatch(params)) {
      problems.add('$key: eist geen AudienceDeck of ExportBundle');
    }
    if (_rawDeckParam.hasMatch(params)) {
      final raw = _rawDeckParam.firstMatch(params)!.group(0);
      problems.add('$key: accepteert nog een rauwe `$raw`');
    }
  });

  if (problems.isEmpty) {
    stdout.writeln(
      'Projectiegrens OK: ${discovered.length} uitvoeroppervlak(ken) gevonden, '
      '${_registry.length} geclassificeerd '
      '(${_registry.values.where((s) => s.kind == SurfaceKind.audience).length}'
      ' naar een ontvanger, '
      '${_registry.values.where((s) => s.kind == SurfaceKind.source).length}'
      ' bron-getrouw).',
    );
    return;
  }

  stderr.writeln('Projectiegrens FAALT:');
  for (final p in problems) {
    stderr.writeln('  - $p');
  }
  exitCode = 1;
}
