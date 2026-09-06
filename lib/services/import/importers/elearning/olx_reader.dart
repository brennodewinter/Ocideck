import 'package:archive/archive.dart';

import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import 'elearning_importer.dart';

/// Leest OLX (Open Learning XML) pakketten (#1997).
///
/// Herkent course.xml met OLX-namespace, haalt course-title en sequential/
/// vertical structuur eruit, en mapt ze naar OciDeck-slides.
class OlxReader extends ElearningFormatReader {
  @override
  SourceDeck read(Archive archive, {required String basename}) {
    final courseXml = _readFile(archive, 'course.xml');
    if (courseXml == null) {
      return SourceDeck(
        title: 'OLX-import',
        slides: [
          makeElearningSlide(
            0,
            'Import-waarschuwing',
            'Geen course.xml gevonden.',
          ),
        ],
      );
    }

    final title =
        _extractXmlValue(courseXml, 'display_name') ??
        _extractXmlAttribute(courseXml, 'course', 'course') ??
        'OLX-import';
    final sequentials = _extractSequentials(courseXml);
    final slides = <SourceSlide>[];

    for (var i = 0; i < sequentials.length; i++) {
      final seq = sequentials[i];
      slides.add(
        makeElearningSlide(
          i,
          seq.title,
          'OLX-sequential: ${seq.url}\n\n'
          '> **Placeholder** — OLX-content is niet volledig geconverteerd. '
          'Bewerk deze slide om de inhoud handmatig toe te voegen.',
        ),
      );
    }

    if (slides.isEmpty) {
      slides.add(
        makeElearningSlide(
          0,
          'OLX-import',
          'Geen sequentials gevonden in course.xml.',
        ),
      );
    }

    return SourceDeck(title: title, slides: slides);
  }

  String? _readFile(Archive archive, String name) {
    for (final f in archive) {
      if (f.name == name) {
        return String.fromCharCodes(f.content as List<int>);
      }
    }
    return null;
  }

  String? _extractXmlValue(String xml, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  String? _extractXmlAttribute(String xml, String tag, String attr) {
    final match = RegExp('<$tag[^>]*$attr="([^"]*)"').firstMatch(xml);
    return match?.group(1)?.trim();
  }

  List<_OlxSequential> _extractSequentials(String xml) {
    final seqs = <_OlxSequential>[];
    final seqRegex = RegExp(r'<sequential[^>]*url_name="([^"]*)"[^>]*>');
    for (final match in seqRegex.allMatches(xml)) {
      final url = match.group(1) ?? '';
      seqs.add(_OlxSequential(title: url, url: url));
    }
    return seqs;
  }
}

class _OlxSequential {
  final String title;
  final String url;
  _OlxSequential({required this.title, required this.url});
}
