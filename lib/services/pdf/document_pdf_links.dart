import '../../utils/heading_anchors.dart';

/// Canonieke en historische fragmenten delen dezelfde PDF-bestemming.
Map<String, String> pdfHeadingLinks(Iterable<String> titles) {
  final anchors = HeadingAnchorIndex(titles, plainText: true);
  return {
    for (final entry in anchors.targets.entries)
      entry.key: 'ocideck-kop-${entry.value}',
  };
}

String pdfHeadingSlug(String text) => headingAnchorBase(text);

/// Returns null for malformed or unresolved fragments, without an external URL.
String? pdfFragmentDestination(String href, Map<String, String> links) {
  try {
    return links[Uri.decodeComponent(href.substring(1))];
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
