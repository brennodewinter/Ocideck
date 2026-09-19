// Document-import-service: zet een Word- of LibreOffice-document om in
// platte Markdown, langs dezelfde fail-closed poort als het openen van een
// vreemd `.md`.
//
// Headless: geen Flutter, geen IO — draait op bytes, dus ook op web. De
// aanroeper (de UI-actie) kiest het bestand; deze service levert de Markdown
// of een [DocumentImportFailure].
//
// De uitvoer gaat door [MarkdownSafetyScanner] vóór de aanroeper hem als
// document opent — dezelfde poort die een vreemd `.md` bij het openen
// tegenhoudt. Een gemaakte `.docx` met een `<script>`-tag in een alinea zou
// zonder deze scan als gewone Markdown in de editor belanden, en bij de
// volgende export als HTML de deur uit gaan.

import 'models/document_conversion.dart';
import 'importers/import_failure.dart';
import 'utils/import_budget.dart';
import '../markdown_safety.dart';
import '../web_asset_store.dart';
import 'importers/docx/docx_document_importer.dart';
import 'importers/odt/odt_document_importer.dart';

/// De uitkomst van een documentimport: de Markdown, of de reden van een
/// mislukking.
class DocumentImportResult {
  const DocumentImportResult.success(
    this.markdown, {
    this.notImported = const [],
  }) : failure = null;

  const DocumentImportResult.failed(this.failure)
    : markdown = null,
      notImported = const [];

  final String? markdown;
  final DocumentImportFailure? failure;

  /// Soorten inhoud die niet meekwamen, één sleutel per weggevallen element
  /// (`'afbeelding'`, `'tekstkader'`, `'groep'`, `'object'`). De UI telt en
  /// vertaalt ze — een lege lijst betekent: alles is mee (#2120).
  final List<String> notImported;

  bool get isSuccess => markdown != null;
}

/// Een documentspecifieke importfout, met dezelfde gestructureerde reden als
/// [ImportFailure] maar zonder de presentatie-specifieke gevallen.
class DocumentImportFailure {
  const DocumentImportFailure(this.message, {this.cause});

  final String message;
  final Object? cause;
}

/// Welk documentformaat de service herkent.
enum DocumentImportFormat { docx, odt }

/// Herkent aan de bestandsnaam of dit een document is dat de import kan
/// omzetten. Gebruikt door de UI om de bestandskiezer te filteren.
bool isImportableDocumentName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return documentImportExtensions.contains(
    name.substring(dot + 1).toLowerCase(),
  );
}

/// De bestandsextensies die de documentimport kent (zonder punt). Eén bron
/// voor de bestandskiezer en de herkenning.
const documentImportExtensions = ['docx', 'odt'];

/// Zet [bytes] (een `.docx` of `.odt`) om in Markdown.
///
/// [filename] wordt alleen gebruikt voor formaatdetectie en foumeldingen —
/// het bestand wordt niet van schijf gelezen. De service kiest de importer
/// aan de hand van de extensie.
DocumentImportResult importDocumentBytes(
  List<int> bytes, {
  required String filename,
  ImportBudget budget = ImportBudget.standard,
}) {
  final format = _detectFormat(filename);
  if (format == null) {
    return DocumentImportResult.failed(
      DocumentImportFailure(
        'Onbekend formaat: $filename. Alleen .docx en .odt worden ondersteund.',
      ),
    );
  }
  try {
    final conversion = switch (format) {
      DocumentImportFormat.docx => convertDocxDetailed(bytes, budget: budget),
      DocumentImportFormat.odt => convertOdtDetailed(bytes, budget: budget),
    };
    final materialized = _materializeImages(conversion);
    // Fail-closed: de importer produceert zelf Markdown, maar de brontekst
    // kan HTML-fragmenten bevatten die als Markdown renderen. Dezelfde poort
    // als het openen van een vreemd `.md` — geen uitvoerbare inhoud erin.
    final findings = MarkdownSafetyScanner.scan(materialized.markdown);
    if (findings.isNotEmpty) {
      return DocumentImportResult.failed(
        DocumentImportFailure(
          'Het document bevat uitvoerbare inhoud (${findings.length} bevindingen) en is geweigerd.',
        ),
      );
    }
    return DocumentImportResult.success(
      materialized.markdown,
      notImported: materialized.notImported,
    );
  } on ImportBudgetException catch (e) {
    return DocumentImportResult.failed(
      DocumentImportFailure(
        'Het document overschrijdt de importlimiet (${e.limitLabel}).',
        cause: e,
      ),
    );
  } on FormatException catch (e) {
    // FormatException is een subtype van Exception — op desktop is dit de
    // normale vangst voor een beschadigd archief. Op web kan de runtime
    // FormatException als InvalidType classificeren; de catch volgt toch.
    return DocumentImportResult.failed(
      DocumentImportFailure(
        'Dit bestand is geen geldig document (beschadigd of onvolledig).',
        cause: e,
      ),
    );
  } on Exception catch (e) {
    return DocumentImportResult.failed(
      DocumentImportFailure('Kon het document niet lezen.', cause: e),
    );
  }
}

DocumentImportFormat? _detectFormat(String filename) {
  final ext = filename.substring(filename.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'docx' => DocumentImportFormat.docx,
    'odt' => DocumentImportFormat.odt,
    _ => null,
  };
}

/// Legt de archiefbytes van elke meegekomen afbeelding in de `mem:`-store
/// en herschrijft `![alt](archiefpad)` naar `![alt](mem:…)`. Dat is hetzelfde
/// tussentijdse contract als de presentatie-import: de documentweergave
/// tekent er direct uit, en de eerste opslag materialiseert ze naar
/// `images/` naast het `.md` (#2120).
///
/// Een afbeelding die het webbudget niet meer past verdwijnt níet stil:
/// haar token wordt uit de Markdown gehaald (geen dode verwijzing naar een
/// pad dat nooit heeft bestaan) én ze telt mee in `notImported`.
DocumentConversion _materializeImages(DocumentConversion conversion) {
  if (conversion.images.isEmpty) return conversion;
  var markdown = conversion.markdown;
  final dropped = [...conversion.notImported];
  for (final image in conversion.images) {
    try {
      final path = WebAssetStore.put(image.bytes, name: image.name);
      markdown = markdown.replaceAll(image.emitted, '![${image.alt}]($path)');
    } on WebAssetBudgetExceeded {
      dropped.add('afbeelding');
      markdown = markdown.replaceAll(image.emitted, '');
    }
  }
  return DocumentConversion(markdown: markdown, notImported: dropped);
}
