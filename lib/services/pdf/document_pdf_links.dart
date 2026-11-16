/// Maps Markdown heading fragments to the PDF's stable outline destinations.
Map<String, String> pdfHeadingLinks(Iterable<String> titles) {
  final links = <String, String>{};
  var index = 0;
  for (final title in titles) {
    final base = pdfHeadingSlug(title);
    var slug = base;
    var suffix = 0;
    while (links.containsKey(slug)) {
      slug = '$base-${++suffix}';
    }
    links[slug] = 'ocideck-kop-${index++}';
  }
  return links;
}

/// Uses the same ASCII fragment convention as the Markdown contents service.
String pdfHeadingSlug(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), '')
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

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
