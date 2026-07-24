import '../importers/importer.dart';
import '../importers/keynote/key_importer.dart';
import '../importers/odp/odp_importer.dart';
import '../importers/pptx/pptx_importer.dart';
import '../models/source_format.dart';

/// Maps a detected [SourceFormat] to the [Importer] that handles it.
///
/// PowerPoint (`.pptx`), LibreOffice Impress (`.odp`) en Apple Keynote
/// (`.key`) staan erin — de drie formaten die de import kent.
class ImporterRegistry {
  ImporterRegistry({List<Importer>? importers}) {
    for (final i
        in importers ?? [PptxImporter(), OdpImporter(), KeyImporter()]) {
      _byFormat[i.format] = i;
    }
  }

  final Map<SourceFormat, Importer> _byFormat = {};

  /// The importer for [format], or `null` when none is registered yet.
  Importer? importerFor(SourceFormat format) => _byFormat[format];

  /// Register or replace the importer for [format] (used by tests to inject
  /// fakes, and by milestone wiring as new importers land).
  void register(SourceFormat format, Importer importer) {
    _byFormat[format] = importer;
  }
}
