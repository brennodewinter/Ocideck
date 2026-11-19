import 'dart:convert';

import '../../models/settings.dart';
import 'website_style_source.dart';

enum WebsiteStyleImage { title, content, logo }

class WebsiteStyleProposal {
  const WebsiteStyleProposal({
    required this.profile,
    required this.accentRoles,
    required this.accentToken,
    required this.images,
    this.palette = const [],
  });

  final ThemeProfile profile;
  final Set<String> accentRoles;
  final String? accentToken;
  final Map<WebsiteStyleImage, Uri> images;
  final List<String> palette;

  factory WebsiteStyleProposal.fromProbe(Object response, Uri url) {
    // WKWebView returns a JS string directly. WebView2 JSON-encodes it.
    Object? decoded = response;
    for (var depth = 0; depth < 2 && decoded is String; depth++) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map || decoded['hasText'] != true) {
      throw const FormatException('No rendered website content');
    }
    final raw = decoded;
    final accent = raw['accent'];
    final token = accent is Map ? accent['token'] : null;
    final roles = accent is Map ? accent['roles'] : null;
    final colors = raw['palette'];
    final stack = raw['fontFamily'] is String
        ? raw['fontFamily'] as String
        : '';
    final (font, preferred) = _websiteFont(stack);
    final titleBackground = _color(raw['titleBackgroundColor'], '#FFFFFF');
    final contentBackground = _color(raw['backgroundColor'], '#FFFFFF');
    final contentText = _color(raw['textColor'], '#222222');
    final profile = ThemeProfile(
      name: url.host,
      accentColor: _color(accent is Map ? accent['value'] : null, contentText),
      textColor: contentText,
      titleTextColor: _color(raw['titleTextColor'], contentText),
      slideBackgroundColor: contentBackground,
      titleBackgroundColor: titleBackground,
      sectionBackgroundColor: titleBackground,
      tableTextColor: contentText,
      fontFamily: font,
      preferredFontFamily: preferred,
    );
    return WebsiteStyleProposal(
      profile: profile,
      palette: colors is List
          ? colors.whereType<String>().where(_hex.hasMatch).take(8).toList()
          : const [],
      accentRoles: roles is List ? roles.whereType<String>().toSet() : const {},
      accentToken: token is String && _tokenName.hasMatch(token) ? token : null,
      images: {
        for (final kind in WebsiteStyleImage.values)
          kind: ?_imageUrl(
            raw[switch (kind) {
              WebsiteStyleImage.title => 'titleImage',
              WebsiteStyleImage.content => 'contentImage',
              WebsiteStyleImage.logo => 'logo',
            }],
          ),
      },
    );
  }
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');
final _tokenName = RegExp(r'^--[A-Za-z0-9_-]{1,80}$');

String _color(Object? raw, String fallback) =>
    raw is String && _hex.hasMatch(raw) ? raw.toUpperCase() : fallback;

Uri? _imageUrl(Object? raw) =>
    raw is String && raw.startsWith('https://') ? websiteStyleUrl(raw) : null;

(String, String?) _websiteFont(String stack) {
  final families = stack
      .split(',')
      .map((name) => name.trim().replaceAll(RegExp(r'''^["']|["']$'''), ''))
      .toList();
  final primary = families.first;
  for (final available in AppSettings.availableFonts) {
    if (available.toLowerCase() == primary.toLowerCase()) {
      return (available, null);
    }
  }
  final generic = switch (families.last.toLowerCase()) {
    'serif' || 'ui-serif' => 'Georgia',
    'monospace' || 'ui-monospace' => 'Courier New',
    _ => 'Arial',
  };
  final fallback =
      families
          .map(
            (family) => AppSettings.availableFonts
                .where(
                  (available) =>
                      family.toLowerCase() == available.toLowerCase(),
                )
                .firstOrNull,
          )
          .nonNulls
          .firstOrNull ??
      generic;
  final genericFonts = [
    'serif',
    'sans-serif',
    'system-ui',
    'monospace',
    'ui-serif',
    'ui-sans-serif',
    'ui-monospace',
    '-apple-system',
  ];
  final preferred =
      !genericFonts.contains(primary.toLowerCase()) &&
          kPreferredFontFamilyPattern.hasMatch(primary)
      ? primary
      : null;
  return (fallback, preferred);
}
