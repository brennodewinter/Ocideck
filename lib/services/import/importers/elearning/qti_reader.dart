import 'package:archive/archive.dart';

import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import 'elearning_importer.dart';

/// Leest QTI 2.x/3.x assessment items en tests (#1994).
///
/// Herkent assessmentTest/assessmentItem structuur, haalt titels en prompts
/// eruit, en zet ze op een dia. De keuzemogelijkheden, de antwoordsleutel en de
/// scoring (outcome declarations, response processing) worden *niet*
/// geconverteerd: de dia draagt in plaats daarvan een placeholderzin die de
/// auteur vraagt de vraag met de hand aan te vullen.
class QtiReader extends ElearningFormatReader {
  @override
  SourceDeck read(Archive archive, {required String basename}) {
    // Zoek het eerste XML-bestand met QTI-namespace.
    String? qtiXml;
    String? qtiName;
    for (final f in archive) {
      if (f.name.endsWith('.xml')) {
        final content = String.fromCharCodes(
          (f.content as List<int>).take(4096).toList(),
        );
        if (content.contains('imsqti_v2') ||
            content.contains('imsqti_v3') ||
            content.contains('http://www.imsglobal.org/xsd/imsqti')) {
          qtiXml = String.fromCharCodes(f.content as List<int>);
          qtiName = f.name;
          break;
        }
      }
    }

    if (qtiXml == null) {
      return SourceDeck(
        title: 'QTI-import',
        slides: [
          makeElearningSlide(
            0,
            'Import-waarschuwing',
            'Geen QTI-XML gevonden in het pakket.',
          ),
        ],
      );
    }

    final title = _extractXmlValue(qtiXml, 'title') ?? 'QTI-import';
    final items = _extractAssessmentItems(qtiXml);
    final slides = <SourceSlide>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      slides.add(
        makeElearningSlide(
          i,
          item.title,
          'QTI-item: ${item.identifier}\n\n'
          '${item.prompt}\n\n'
          '> **Placeholder** — QTI response processing en scoring zijn niet '
          'volledig geconverteerd. Bewerk deze slide om de vraag en antwoorden '
          'handmatig toe te voegen.',
        ),
      );
    }

    if (slides.isEmpty) {
      slides.add(
        makeElearningSlide(
          0,
          'QTI-import',
          'Geen assessment items gevonden in $qtiName.',
        ),
      );
    }

    return SourceDeck(title: title, slides: slides);
  }

  String? _extractXmlValue(String xml, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  List<_QtiItem> _extractAssessmentItems(String xml) {
    final items = <_QtiItem>[];
    final itemRegex = RegExp(
      r'<assessmentItem[^>]*identifier="([^"]*)"[^>]*>(.*?)</assessmentItem>',
      dotAll: true,
    );
    for (final match in itemRegex.allMatches(xml)) {
      final identifier = match.group(1) ?? '';
      final inner = match.group(2) ?? '';
      final title = _extractXmlValue(inner, 'title') ?? identifier;
      final prompt =
          _extractXmlValue(inner, 'prompt') ??
          _extractXmlValue(inner, 'itemBody') ??
          '';
      items.add(_QtiItem(identifier: identifier, title: title, prompt: prompt));
    }
    return items;
  }
}

class _QtiItem {
  final String identifier;
  final String title;
  final String prompt;
  _QtiItem({
    required this.identifier,
    required this.title,
    required this.prompt,
  });
}
