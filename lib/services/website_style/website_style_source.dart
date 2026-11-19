import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../feeds/feed_fetch.dart';
import '../file_service.dart' show FileService;
import '../image_service.dart';

bool _allowedUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

Uri? websiteStyleUrl(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  return uri != null && _allowedUrl(uri) ? uri.removeFragment() : null;
}

const _requestTimeout = Duration(seconds: 8);
const _maxStylesheets = 10;
const _maxHtmlBytes = 700 * 1024;
const _maxCssBytes = 256 * 1024;
const _maxTotalCss = 800 * 1024;
const _maxSnapshotLength = 1800000;

typedef WebsiteResourceFetcher =
    Future<FeedFetchResult> Function(Uri url, {required int maxBytes});

Future<FeedFetchResult> _fetch(Uri url, {required int maxBytes}) => fetchFeed(
  url,
  maxBytes: maxBytes,
  timeout: _requestTimeout,
  totalTimeout: _requestTimeout,
  allowUrl: _allowedUrl,
);

class WebsiteStyleSnapshot {
  const WebsiteStyleSnapshot({
    required this.url,
    required this.html,
    required this.incompleteStylesheets,
  });

  final Uri url;
  final String html;
  final bool incompleteStylesheets;
}

Future<WebsiteStyleSnapshot> loadWebsiteStyleSnapshot(
  Uri url, {
  WebsiteResourceFetcher fetch = _fetch,
}) async {
  if (!_allowedUrl(url)) throw const FormatException('Invalid website URL');
  final page = await fetch(url, maxBytes: _maxHtmlBytes);
  if (!page.ok) throw const FormatException('Website could not be read');
  final pageUrl = page.finalUrl!;
  final document = html.parse(utf8.decode(page.bytes!, allowMalformed: true));
  final base =
      _resolve(
        pageUrl,
        document.querySelector('base[href]')?.attributes['href'],
      ) ??
      pageUrl;
  final styleNodes = document.querySelectorAll(
    'style, link[rel~="stylesheet"]',
  );
  final linkedNodes = styleNodes
      .where((node) => node.localName == 'link')
      .toList();
  final urls = <Uri>{
    for (final node in linkedNodes.take(_maxStylesheets))
      ?_resolve(base, node.attributes['href']),
  };
  final fetched = await _fetchStylesheets(urls, fetch);
  final cssSources = <({String css, Uri base, String? media})>[
    for (final node in styleNodes) ?_readStylesheet(node, base, fetched),
  ];
  final imports = <Uri>{};
  for (final source in cssSources) {
    for (final reference in _stylesheetImports(
      source.css,
    ).take(_maxStylesheets)) {
      final address = _resolve(
        source.base,
        reference[1] ?? reference[2] ?? reference[3],
      );
      if (address == null || fetched.containsKey(address)) continue;
      if (imports.length >= _maxStylesheets - urls.length) break;
      imports.add(address);
    }
  }
  fetched.addAll(await _fetchStylesheets(imports, fetch));

  var availableCss = _maxTotalCss;
  var incomplete = cssSources.length < styleNodes.length;
  final safeStyles = <dom.Element>[];
  for (final source in cssSources) {
    var cursor = 0;
    final css = StringBuffer();
    for (final reference in _stylesheetImports(source.css)) {
      css.write(
        _rewriteCssUrls(
          source.css.substring(cursor, reference.start),
          source.base,
        ),
      );
      cursor = reference.end;
      final address = _resolve(
        source.base,
        reference[1] ?? reference[2] ?? reference[3],
      );
      final resource = fetched[address];
      final media = reference[4]!.trim();
      if (resource == null ||
          media.startsWith('layer') ||
          media.startsWith('supports(')) {
        incomplete = true;
        continue;
      }
      final imported = utf8.decode(resource.bytes!, allowMalformed: true);
      final nested = _stylesheetImports(imported).lastOrNull;
      if (nested != null) incomplete = true;
      final rules = _rewriteCssUrls(
        nested == null ? imported : imported.substring(nested.end),
        resource.finalUrl!,
      );
      if (rules.length + css.length > availableCss) {
        incomplete = true;
        continue;
      }
      css.write(media.isEmpty ? rules : '@media $media {$rules}');
    }
    css.write(_rewriteCssUrls(source.css.substring(cursor), source.base));
    if (css.length > availableCss) {
      incomplete = true;
      continue;
    }
    availableCss -= css.length;
    final style = dom.Element.tag('style')
      ..text = css.toString().replaceAll(_closingStyleTag, r'<\/style');
    if (source.media case final media?) style.attributes['media'] = media;
    safeStyles.add(style);
  }

  for (final node in document.querySelectorAll(_discardedElements)) {
    node.remove();
  }
  for (final node in document.querySelectorAll('*')) {
    _keepInertAttributes(node, base);
  }

  final head = document.head!;
  head.nodes.clear();
  head.append(dom.Element.tag('meta')..attributes['charset'] = 'utf-8');
  head.append(
    dom.Element.tag('meta')..attributes['name'] = 'ocideck-style-snapshot',
  );
  head.append(
    dom.Element.tag('meta')
      ..attributes.addAll({
        'http-equiv': 'Content-Security-Policy',
        'content':
            "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'",
      }),
  );
  head.append(
    dom.Element.tag('meta')
      ..attributes.addAll({
        'name': 'viewport',
        'content': 'width=device-width, initial-scale=1',
      }),
  );
  for (final style in safeStyles) {
    head.append(style);
  }
  final markup = '<!doctype html>${document.documentElement!.outerHtml}';
  if (markup.length > _maxSnapshotLength) {
    throw const FormatException('Website snapshot is too large');
  }
  return WebsiteStyleSnapshot(
    url: pageUrl,
    html: markup,
    incompleteStylesheets: incomplete,
  );
}

Future<Map<Uri, FeedFetchResult?>> _fetchStylesheets(
  Set<Uri> urls,
  WebsiteResourceFetcher fetch,
) async => Map.fromEntries(
  await Future.wait(
    urls.map((url) async {
      try {
        final result = await fetch(url, maxBytes: _maxCssBytes);
        return MapEntry(url, result.ok ? result : null);
      } on Exception {
        return MapEntry<Uri, FeedFetchResult?>(url, null);
      }
    }),
  ),
);

({String css, Uri base, String? media})? _readStylesheet(
  dom.Element node,
  Uri base,
  Map<Uri, FeedFetchResult?> fetched,
) {
  final media = node.attributes['media'];
  if (node.localName == 'style') {
    return (css: node.text, base: base, media: media);
  }
  final resource = fetched[_resolve(base, node.attributes['href'])];
  if (resource == null) return null;
  return (
    css: utf8.decode(resource.bytes!, allowMalformed: true),
    base: resource.finalUrl!,
    media: media,
  );
}

const _discardedElements =
    'script, noscript, style, link, meta, base, iframe, frame, frameset, '
    'object, embed, applet, portal, template, svg, math, video, audio, source, '
    'track, input[type="file"]';
const _visualAttributes = {
  'class',
  'id',
  'role',
  'style',
  'hidden',
  'open',
  'alt',
  'width',
  'height',
  'type',
  'dir',
  'lang',
  'disabled',
  'aria-label',
  'aria-hidden',
  'aria-current',
  'aria-level',
};
final _cssImport = RegExp(
  r'''@import\s+(?:url\(\s*["']?([^"')]+)["']?\s*\)|"([^"]+)"|'([^']+)')\s*([^;]*);''',
  caseSensitive: false,
);
final _cssPreamble = RegExp(
  r'(?:\s+|/\*[\s\S]*?\*/|@charset\s+"[^"]*"\s*;)+',
  caseSensitive: false,
);

Iterable<Match> _stylesheetImports(String css) sync* {
  // CSS imports precede normal declarations. Reading the preamble avoids
  // interpreting text inside unrelated comments or CSS string values as URLs.
  var cursor = 0;
  while (cursor < css.length) {
    cursor = _cssPreamble.matchAsPrefix(css, cursor)?.end ?? cursor;
    final match = _cssImport.matchAsPrefix(css, cursor);
    if (match == null) break;
    yield match;
    cursor = match.end;
  }
}

final _closingStyleTag = RegExp(r'</style', caseSensitive: false);
final _cssUrl = RegExp(
  r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)"']+))\s*\)''',
  caseSensitive: false,
);

Uri? _resolve(Uri base, String? source) {
  if (source == null || source.trim().isEmpty) return null;
  final parsed = Uri.tryParse(source.trim());
  if (parsed == null) return null;
  final url = base.resolveUri(parsed).removeFragment();
  return _allowedUrl(url) ? url : null;
}

String _rewriteCssUrls(String value, Uri base) => value.replaceAllMapped(
  _cssUrl,
  (match) {
    final url = _resolve(base, match[1] ?? match[2] ?? match[3]);
    if (url == null) return 'url("about:blank")';
    final safe = url.toString().replaceAll('"', '%22').replaceAll('\\', '%5C');
    return 'url("$safe")';
  },
);

void _keepInertAttributes(dom.Element node, Uri base) {
  final source = node.localName == 'img'
      ? _resolve(base, node.attributes['src'] ?? node.attributes['data-src'])
      : null;
  final isLink = node.localName == 'a' && node.attributes.containsKey('href');
  node.attributes.removeWhere(
    (name, _) =>
        name is! String ||
        (!_visualAttributes.contains(name) && !name.startsWith('data-')),
  );
  node.attributes.remove('data-ocideck-image');
  if (source != null) node.attributes['data-ocideck-image'] = source.toString();
  if (isLink) node.attributes['href'] = '#';
  if (node.attributes['style'] case final style?) {
    node.attributes['style'] = _rewriteCssUrls(style, base);
  }
}

Future<Uint8List> loadWebsiteStyleImage(Uri url) async {
  if (!_allowedUrl(url)) throw const FormatException('Invalid image URL');
  final result = await _fetch(
    url,
    maxBytes: FileService.maxStyleProfileLogoBytes,
  );
  final bytes = result.bytes;
  final mime = bytes == null ? null : ImageService.imageMimeFromBytes(bytes);
  if (bytes == null || mime == null || mime == 'image/svg+xml') {
    throw const FormatException('Website image could not be read');
  }
  return bytes;
}
