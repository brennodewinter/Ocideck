import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

/// Bouwt de [ExportBundle] die `ExportService.export()` verlangt.
///
/// Sinds de markdown en de sprekersnotities alleen nog via een bundel naar
/// binnen mogen, kan een test ze niet meer als losse string meegeven — en dat
/// is de bedoeling: een export die niet door [PrivacyProjection] is gegaan,
/// hoort onmogelijk te zijn, ook vanuit een test. Deze hulp doet die projectie
/// dus écht, in plaats van hem te omzeilen.
///
/// [markdown] overschrijft alleen wat er in het HTML-bestand belandt; laat hem
/// weg en de markdown wordt uit het geprojecteerde deck gegenereerd, precies
/// zoals de shell dat doet.
ExportBundle bundleFor(Deck deck, {String? markdown}) {
  final audience = PrivacyProjection.forAudience(deck);
  return ExportBundle(
    audience: audience,
    markdown:
        markdown ??
        MarkdownService().generateDeck(audience.deck, forExport: true),
    manifest: RedactionManifest.empty,
    privacySummary: PrivacyExportSummary.empty,
  );
}

/// Een bundel voor een deck dat alleen uit sprekersnotities hoeft te bestaan:
/// één slide per element van [notes].
ExportBundle bundleWithNotes(List<String> notes) => bundleFor(
  Deck(
    title: 'Notities',
    slides: [
      for (var i = 0; i < notes.length; i++)
        Slide(id: 'n$i', type: SlideType.title, notes: notes[i]),
    ],
  ),
);
