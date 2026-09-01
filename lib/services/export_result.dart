/// Wat een export oplevert: het formaat, en de uitkomst.
///
/// Los van `export_service.dart` omdat het data is en geen dienst — en omdat
/// die dienst tegen zijn regelplafond zat. `export_service.dart` exporteert dit
/// bestand weer, zodat de tientallen aanroepers die `ExportFormat` uit de
/// dienst importeren niets hoeven te veranderen.
library;

import 'classification_policy.dart' show ExportDecision;

enum ExportFormat { pdf, pptx, odp, html, latex }

extension ExportFormatExtension on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.pdf:
        return 'PDF';
      case ExportFormat.pptx:
        return 'PowerPoint (PPTX)';
      case ExportFormat.odp:
        return 'OpenDocument (ODP)';
      case ExportFormat.html:
        return 'HTML (Marp, self-contained)';
      case ExportFormat.latex:
        return 'LaTeX (Beamer)';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.pdf:
        return '.pdf';
      case ExportFormat.pptx:
        return '.pptx';
      case ExportFormat.odp:
        return '.odp';
      case ExportFormat.html:
        return '.html';
      case ExportFormat.latex:
        return '.tex';
    }
  }
}

/// Waarom een export niet lukte, wanneer de dienst dat als *beslissing* weet en
/// niet als zin — de dienst kent de taal van de gebruiker niet (#576). De schil
/// maakt er een zin van.
enum ExportFailure {
  /// De browser nam de download niet aan. Zegt niets over of een eerder
  /// aangeboden bestand aankwam: dat kan de pagina niet zien (#1902).
  downloadNotStarted,
}

class ExportResult {
  final bool success;
  final String? outputPath;
  final String? error;

  /// Gezet wanneer de reden een beslissing is en geen zin. Zie [ExportFailure].
  final ExportFailure? failure;

  /// Gezet wanneer het classificatiebeleid de export tegenhield.
  ///
  /// Een beslissing en geen zin: de dienst kent de taal van de gebruiker niet,
  /// en een weigering die het TLP-niveau in de zin noemt heeft geen letterlijke
  /// vorm om op te vertalen (#576). De schil maakt er een zin van met
  /// `exportBlockMessage`.
  final ExportDecision? classificationDecision;

  const ExportResult._({
    required this.success,
    this.outputPath,
    this.error,
    this.failure,
    this.classificationDecision,
  });

  factory ExportResult.ok(String path) =>
      ExportResult._(success: true, outputPath: path);
  factory ExportResult.fail(String error) =>
      ExportResult._(success: false, error: error);
  factory ExportResult.failed(ExportFailure failure) =>
      ExportResult._(success: false, failure: failure);
  factory ExportResult.blockedByClassification(ExportDecision decision) =>
      ExportResult._(success: false, classificationDecision: decision);
}
