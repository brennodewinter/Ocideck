import 'package:archive/archive.dart';

import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import 'elearning_importer.dart';

/// Leest AICC course-structure (.crs/.au/.cst/.des) (#1996).
///
/// AICC gebruikt key-value secties in platte tekst. De importer herkent
/// titels en beschrijvingen uit .crs, en les-elementen uit .au/.cst.
class AiccReader extends ElearningFormatReader {
  @override
  SourceDeck read(Archive archive, {required String basename}) {
    String? crsContent;
    String? auContent;
    for (final f in archive) {
      final lower = f.name.toLowerCase();
      if (lower.endsWith('.crs')) {
        crsContent = String.fromCharCodes(f.content as List<int>);
      } else if (lower.endsWith('.au')) {
        auContent = String.fromCharCodes(f.content as List<int>);
      }
    }

    final title =
        _extractCrsTitle(crsContent) ??
        basename.replaceAll(RegExp(r'\.[^.]+$'), '');
    final slides = <SourceSlide>[];

    if (auContent != null) {
      final auUnits = _parseAuUnits(auContent);
      for (var i = 0; i < auUnits.length; i++) {
        final unit = auUnits[i];
        slides.add(
          makeElearningSlide(
            i,
            unit.title,
            'AICC-unit: ${unit.id}\n\n'
            'Bronbestand: ${unit.path}\n\n'
            '> **Placeholder** — AICC-content is niet volledig geconverteerd. '
            'Bewerk deze slide om de inhoud handmatig toe te voegen.',
          ),
        );
      }
    }

    if (slides.isEmpty) {
      slides.add(
        makeElearningSlide(
          0,
          'AICC-import',
          'Geen les-elementen (.au) gevonden in het pakket.',
        ),
      );
    }

    return SourceDeck(title: title, slides: slides);
  }

  String? _extractCrsTitle(String? crs) {
    if (crs == null) return null;
    final match = RegExp(r'course_title\s*=\s*(.*)').firstMatch(crs);
    return match?.group(1)?.trim();
  }

  List<_AuUnit> _parseAuUnits(String au) {
    final units = <_AuUnit>[];
    for (final line in au.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(';')) continue;
      final parts = trimmed.split(',');
      if (parts.length >= 3) {
        units.add(
          _AuUnit(
            id: parts[0].trim(),
            title: parts[2].trim(),
            path: parts.length > 4 ? parts[4].trim() : '',
          ),
        );
      }
    }
    return units;
  }
}

class _AuUnit {
  final String id;
  final String title;
  final String path;
  _AuUnit({required this.id, required this.title, required this.path});
}
