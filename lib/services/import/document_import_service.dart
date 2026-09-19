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

import 'importers/import_failure.dart';
import 'models/source_document_style.dart';
import 'utils/import_budget.dart';
import '../markdown_safety.dart';
import 'importers/docx/docx_document_importer.dart';
import 'importers/odt/odt_document_importer.dart';

/// De uitkomst van een documentimport: de Markdown mét de huisstijl van de
/// bron (#2119), of de reden van een mislukking.
class DocumentImportResult {
  const DocumentImportResult.success(
    this.markdown, {
    this.style = SourceDocumentStyle.empty,
    this.skippedImages = 0,
  }) : failure = null;

  const DocumentImportResult.failed(this.failure)
    : markdown = null,
      style = SourceDocumentStyle.empty,
      skippedImages = 0;

  final String? markdown;
  final DocumentImportFailure? failure;

  /// Wat de bron aan huisstijl droeg; leeg als er niets te halen viel.
  final SourceDocumentStyle style;

  /// Beelden in de lopende tekst die niet mee konden (#2120): de melding na
  /// de import telt ze, zodat er niets stil verdwijnt.
  final int skippedImages;

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
    final (markdown, style, skippedImages) = switch (format) {
      DocumentImportFormat.docx => _unpackDocx(bytes, budget),
      DocumentImportFormat.odt => _unpackOdt(bytes, budget),
    };
    // Fail-closed: de importer produceert zelf Markdown, maar de brontekst
    // kan HTML-fragmenten bevatten die als Markdown renderen. Dezelfde poort
    // als het openen van een vreemd `.md` — geen uitvoerbare inhoud erin.
    final findings = MarkdownSafetyScanner.scan(markdown);
    if (findings.isNotEmpty) {
      return DocumentImportResult.failed(
        DocumentImportFailure(
          'Het document bevat uitvoerbare inhoud (${findings.length} bevindingen) en is geweigerd.',
        ),
      );
    }
    return DocumentImportResult.success(
      markdown,
      style: style,
      skippedImages: skippedImages,
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

(String, SourceDocumentStyle, int) _unpackDocx(
  List<int> bytes,
  ImportBudget budget,
) {
  final result = importDocx(bytes, budget: budget);
  return (result.markdown, result.style, result.skippedImages);
}

(String, SourceDocumentStyle, int) _unpackOdt(
  List<int> bytes,
  ImportBudget budget,
) {
  final result = importOdt(bytes, budget: budget);
  return (result.markdown, result.style, result.skippedImages);
}

DocumentImportFormat? _detectFormat(String filename) {
  final ext = filename.substring(filename.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'docx' => DocumentImportFormat.docx,
    'odt' => DocumentImportFormat.odt,
    _ => null,
  };
}
