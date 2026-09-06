import 'package:archive/archive.dart';

import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import 'elearning_importer.dart';

/// Leest IMS Manifest / SCORM-pakketten (#1993).
///
/// Herkent `imsmanifest.xml` aan de root, parseert organizations/item-
/// hiërarchie, en mapt items naar OciDeck-slides. Resources (HTML, afbeeldingen)
/// worden als placeholders bewaard met een verwijzing naar het bronbestand.
class ImsManifestReader extends ElearningFormatReader {
  @override
  SourceDeck read(Archive archive, {required String basename}) {
    final manifest = _readFile(archive, 'imsmanifest.xml');
    if (manifest == null) {
      return SourceDeck(
        title: _titleFromBasename(basename),
        slides: [_placeholderSlide(0, 'Geen imsmanifest.xml gevonden')],
      );
    }

    final title =
        _extractXmlValue(manifest, 'title') ?? _titleFromBasename(basename);
    final items = _extractItems(manifest);
    final slides = <SourceSlide>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      slides.add(
        makeElearningSlide(
          i,
          item.title,
          'SCORM-item: ${item.identifier}\n\n'
          'Bronbestand: ${item.href}\n\n'
          '> **Placeholder** — de inhoud van dit SCORM-item is niet '
          'volledig geconverteerd. Bewerk deze slide om de inhoud handmatig '
          'toe te voegen, of gebruik de oorspronkelijke bron.',
        ),
      );
    }

    if (slides.isEmpty) {
      slides.add(
        _placeholderSlide(0, 'Geen items gevonden in imsmanifest.xml'),
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

  String _titleFromBasename(String basename) {
    final withoutExt = basename.replaceAll(RegExp(r'\.[^.]+$'), '');
    return withoutExt.isEmpty ? 'SCORM-import' : withoutExt;
  }

  String? _extractXmlValue(String xml, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  List<_ImsItem> _extractItems(String xml) {
    final items = <_ImsItem>[];
    final itemRegex = RegExp(
      r'<item[^>]*identifier="([^"]*)"[^>]*>(.*?)</item>',
      dotAll: true,
    );
    for (final match in itemRegex.allMatches(xml)) {
      final identifier = match.group(1) ?? '';
      final inner = match.group(2) ?? '';
      final title = _extractXmlValue(inner, 'title') ?? identifier;
      items.add(_ImsItem(identifier: identifier, title: title, href: ''));
    }
    return items;
  }

  SourceSlide _placeholderSlide(int index, String message) {
    return makeElearningSlide(index, 'Import-waarschuwing', message);
  }
}

class _ImsItem {
  final String identifier;
  final String title;
  final String href;
  _ImsItem({required this.identifier, required this.title, required this.href});
}
