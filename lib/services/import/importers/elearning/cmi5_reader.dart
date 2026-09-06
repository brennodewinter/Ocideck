import 'package:archive/archive.dart';

import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import 'elearning_importer.dart';

/// Leest cmi5 course packages en xAPI activity metadata (#1995).
///
/// Herkent cmi5.xml of losse xAPI JSON, haalt course-title en AU-structuur
/// eruit. OciDeck wordt geen LRS en stuurt geen statements.
class Cmi5Reader extends ElearningFormatReader {
  @override
  SourceDeck read(Archive archive, {required String basename}) {
    final cmi5Xml = _readFile(archive, 'cmi5.xml');
    if (cmi5Xml != null) {
      return _parseCmi5(cmi5Xml, basename);
    }

    // Losse xAPI JSON in het archief.
    for (final f in archive) {
      if (f.name.endsWith('.json')) {
        final content = String.fromCharCodes(f.content as List<int>);
        if (content.contains('"verb"') || content.contains('"actor"')) {
          return _parseXapiJson(content, basename);
        }
      }
    }

    return SourceDeck(
      title: 'xAPI/cmi5-import',
      slides: [
        makeElearningSlide(
          0,
          'Import-waarschuwing',
          'Geen cmi5.xml of xAPI JSON gevonden.',
        ),
      ],
    );
  }

  SourceDeck _parseCmi5(String xml, String basename) {
    final title =
        _extractXmlAttribute(xml, 'course', 'title') ??
        basename.replaceAll(RegExp(r'\.[^.]+$'), '');
    final aus = _extractAus(xml);
    final slides = <SourceSlide>[];

    for (var i = 0; i < aus.length; i++) {
      final au = aus[i];
      slides.add(
        makeElearningSlide(
          i,
          au.title,
          'cmi5 AU: ${au.id}\n\n'
          'URL: ${au.url}\n\n'
          '> **Placeholder** — cmi5 AU-content is niet volledig geconverteerd. '
          'Bewerk deze slide om de inhoud handmatig toe te voegen.',
        ),
      );
    }

    if (slides.isEmpty) {
      slides.add(
        makeElearningSlide(
          0,
          'cmi5-import',
          'Geen AU-elementen gevonden in cmi5.xml.',
        ),
      );
    }

    return SourceDeck(title: title, slides: slides);
  }

  SourceDeck _parseXapiJson(String json, String basename) {
    // xAPI JSON is een activity definition of een statement. Haal de naam eruit.
    final nameMatch = RegExp(
      r'"name"\s*:\s*\{[^}]*"[^"]*"\s*:\s*"([^"]*)"',
    ).firstMatch(json);
    final title = nameMatch?.group(1) ?? 'xAPI-activiteit';

    return SourceDeck(
      title: title,
      slides: [
        makeElearningSlide(
          0,
          title,
          'xAPI-activiteit geïmporteerd uit $basename.\n\n'
          '> **Placeholder** — xAPI activity metadata is als structuur '
          'geïmporteerd. De runtime-statements worden niet uitgevoerd.',
        ),
      ],
    );
  }

  String? _readFile(Archive archive, String name) {
    for (final f in archive) {
      if (f.name == name) {
        return String.fromCharCodes(f.content as List<int>);
      }
    }
    return null;
  }

  String? _extractXmlAttribute(String xml, String tag, String attr) {
    final match = RegExp('<$tag[^>]*$attr="([^"]*)"').firstMatch(xml);
    return match?.group(1)?.trim();
  }

  List<_Cmi5Au> _extractAus(String xml) {
    final aus = <_Cmi5Au>[];
    final auRegex = RegExp(r'<au[^>]*id="([^"]*)"[^>]*>', dotAll: true);
    for (final match in auRegex.allMatches(xml)) {
      final id = match.group(1) ?? '';
      final fullMatch = match.group(0) ?? '';
      final url = _extractXmlAttribute(fullMatch, 'au', 'url') ?? '';
      final title = _extractXmlAttribute(fullMatch, 'au', 'title') ?? id;
      aus.add(_Cmi5Au(id: id, title: title, url: url));
    }
    return aus;
  }
}

class _Cmi5Au {
  final String id;
  final String title;
  final String url;
  _Cmi5Au({required this.id, required this.title, required this.url});
}
