// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (afbeeldingen inbedden als data:-URI); all imports live in the main library
// file. These were private MarpHtmlService helpers; as top-level private
// functions they share the library and are called by bare name.
part of '../marp_html_service.dart';

Future<({String markdown, List<String> dataUris})> _embedHtmlImages(
  String markdown,
  HtmlImageResolver? embedImage,
  int maxEmbedBytes,
  bool continuous,
  ThemeProfile? theme,
  TlpLevel tlp,
  Map<String, String> documentFields,
  MarpHtmlService service,
) async {
  final embedded = await _embedImages(markdown, embedImage, maxEmbedBytes);
  final chromeTheme = theme ?? const ThemeProfile();
  if (!continuous || !_hasDocumentChrome(chromeTheme, tlp)) {
    return embedded;
  }
  return _withDocumentChrome(
    embedded,
    chromeTheme,
    tlp,
    documentFields,
    embedImage,
    service.loadBytes,
    maxEmbedBytes,
  );
}

Future<String?> _themeLogoDataUri(
  String path,
  HtmlImageResolver? embedImage,
  Future<Uint8List> Function(String asset) loadBytes,
) async {
  if (!isBundledAssetPath(path)) return embedImage?.call(path);
  try {
    final bytes = await loadBytes(bundledAssetKey(path));
    final lower = path.toLowerCase();
    final mime = lower.endsWith('.svg')
        ? 'image/svg+xml'
        : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
        ? 'image/jpeg'
        : lower.endsWith('.gif')
        ? 'image/gif'
        : 'image/png';
    return 'data:$mime;base64,${base64.encode(bytes)}';
  } catch (e) {
    logWarning('MarpHtmlService: documentlogo niet ingesloten', e);
    return null;
  }
}

/// De breedte van een dia in de zelfstandige HTML-export, in px. Moet gelijk
/// blijven aan `.slide{width:1280px}` in [_structuralCss]/[_themedCss]: de
/// logo-inzet en de vrijgehouden strook worden op deze breedte berekend, zoals
/// [logoSafeReserve] dat op de renderbreedte van een dia doet.
const double _kSlidePxWidth = 1280;

/// De opmaak die het presentatielogo op elke logo-dia van de zelfstandige
/// HTML-export legt (dia-modus). De tegenhanger van [_withDocumentChrome], dat
/// hetzelfde logo in de doorlopende documentmodus als kop/voetband meestuurt.
///
/// Leeg als het thema geen logo draagt, of als het niet ingesloten kan worden
/// (ontbrekend bestand) — dan blijft de export zoals hij was. Anders spiegelt
/// de opmaak [_LogoOverlay] (overlays.dart) en [logoSafeReserve]
/// (rich_text_layout.dart): eenzelfde `logoSize`-vak met dezelfde fractionele
/// hoekinzet, en dezelfde vrijgehouden strook, zodat de HTML precies het beeld
/// toont dat de presentator, de beamer en de PDF/PPTX al gaven — de dia is er
/// even breed (1280px) als het ijkbeeld van de overlay.
///
/// Via `::before` op de sectie en niet als `<img>` in de dia: het renderscript
/// wist de `innerHTML` van elke sectie voordat het de markdown erin zet, dus een
/// echt logo-element zou die reset niet overleven. Een pseudo-element wel. De
/// data:-URI in `url(...)` valt binnen `img-src ... data:` van de CSP, net als
/// de kattenpoot-opsommingstekens.
Future<String> _presentationLogoCss(
  ThemeProfile theme,
  HtmlImageResolver? embedImage,
  Future<Uint8List> Function(String asset) loadBytes,
) async {
  final path = effectiveSlideLogoPath(theme);
  if (path == null || path.trim().isEmpty) return '';
  final uri = await _themeLogoDataUri(path, embedImage, loadBytes);
  if (uri == null) return '';

  final size = theme.logoSize;
  final atTop = theme.logoPosition.startsWith('top');
  final vertical = atTop ? 'top' : 'bottom';
  final vInset =
      (size * (atTop ? kLogoTopInsetFraction : kLogoBottomInsetFraction))
          .round();
  final horizontal = theme.logoPosition.endsWith('left') ? 'left' : 'right';
  final hInset = (size * kLogoHorizontalInsetFraction).round();
  // De dia is 1280px breed; op die breedte reserveert de app dezelfde strook.
  final reserve = logoSafeReserve(_kSlidePxWidth, theme).round();
  final safePad = atTop ? 'padding-top' : 'padding-bottom';

  return '.slide.logo-safe::before{content:"";position:absolute;'
      'width:${size}px;height:${size}px;'
      'background:url("$uri") center/contain no-repeat;'
      '$vertical:${vInset}px;$horizontal:${hInset}px;'
      'pointer-events:none;z-index:1}'
      '.slide.logo-safe{$safePad:${reserve}px}';
}

String _documentChromeMarkdownHtml(String markdown) => markdown
    .trim()
    .split('\n')
    .map(
      (line) => parseInlineRuns(line).map((run) {
        var html = MarpHtmlService._htmlText(
          run.math ? '\$${run.text}\$' : run.text,
        );
        if (run.code) html = '<code>$html</code>';
        if (run.strike) html = '<del>$html</del>';
        if (run.italic) html = '<em>$html</em>';
        if (run.bold) html = '<strong>$html</strong>';
        final link = _safeDocumentChromeLink(run.link);
        if (link != null && link.isNotEmpty) {
          html = '<a href="${MarpHtmlService._htmlAttr(link)}">$html</a>';
        }
        return html;
      }).join(),
    )
    .join('<br>');

String? _safeDocumentChromeLink(String? raw) {
  final link = raw?.trim();
  if (link == null || link.isEmpty) return null;
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  if (uri.scheme.isEmpty ||
      const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
    return link;
  }
  return null;
}

bool _hasDocumentChrome(ThemeProfile theme, TlpLevel tlp) =>
    theme.effectiveDocumentLogoPath?.trim().isNotEmpty == true ||
    theme.documentHeaderText.trim().isNotEmpty ||
    theme.documentFooterText.trim().isNotEmpty ||
    theme.documentShowPageNumbers ||
    tlp != TlpLevel.none;

Future<({String markdown, List<String> dataUris})> _withDocumentChrome(
  ({String markdown, List<String> dataUris}) embedded,
  ThemeProfile theme,
  TlpLevel tlp,
  Map<String, String> documentFields,
  HtmlImageResolver? embedImage,
  Future<Uint8List> Function(String asset) loadBytes,
  int maxEmbedBytes,
) async {
  final uris = [...embedded.dataUris];
  String logo = '';
  final logoPath = theme.effectiveDocumentLogoPath?.trim();
  if (logoPath != null && logoPath.isNotEmpty) {
    final logoUri = await _themeLogoDataUri(logoPath, embedImage, loadBytes);
    if (logoUri != null) {
      var logoIndex = uris.indexOf(logoUri);
      if (logoIndex < 0) {
        final used = uris.fold<int>(
          logoUri.length,
          (sum, uri) => sum + uri.length,
        );
        if (used > maxEmbedBytes) {
          throw HtmlEmbedBudgetExceeded(
            usedBytes: used,
            limitBytes: maxEmbedBytes,
          );
        }
        logoIndex = uris.length;
        uris.add(logoUri);
      }
      logo = '<img src="$_imagePlaceholder$logoIndex" alt="">';
    }
  }
  final logoAtTop =
      logo.isNotEmpty && theme.documentLogoPosition.startsWith('top');
  final logoAtRight = theme.documentLogoPosition.endsWith('right');
  String band(String kind, String text, {required bool showPage}) {
    final inBand = kind == 'header' ? logoAtTop : logo.isNotEmpty && !logoAtTop;
    final logoHtml = inBand
        ? '<span class="document-logo ${logoAtRight ? 'right' : 'left'}">$logo</span>'
        : '';
    final page = showPage
        ? '<span class="document-page-number" aria-label="Pagina"></span>'
        : '';
    final marking = tlp == TlpLevel.none
        ? ''
        : '<span class="document-tlp" style="color:#${(tlp.foreground & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}">${MarpHtmlService._htmlText(tlp.label)}</span>';
    return '<div class="document-$kind">'
        '${inBand && !logoAtRight ? logoHtml : ''}'
        '<span class="document-$kind-text">${_documentChromeMarkdownHtml(text)}</span>'
        '$page$marking${inBand && logoAtRight ? logoHtml : ''}</div>';
  }

  final header = band(
    'header',
    resolveDocumentChromeTemplate(
      theme.documentHeaderText.trim(),
      documentFields,
    ),
    showPage: false,
  );
  final footer = band(
    'footer',
    resolveDocumentChromeTemplate(
      theme.documentFooterText.trim(),
      documentFields,
    ),
    showPage: theme.documentShowPageNumbers,
  );
  // De front matter blijft bovenaan: zij hoort op teken 0 te beginnen, anders
  // ziet noch de strip noch [MarpHtmlService.signatureFields] haar nog staan
  // (zie [_splitFrontMatter]). De band schuift er dus ónder, niet ervoor.
  final source = _splitFrontMatter(embedded.markdown);
  return (
    markdown: '${source.head}$header\n\n${source.body}\n\n$footer',
    dataUris: uris,
  );
}

// ── Afbeeldingen → data:-URI ──────────────────────────────────────────────

/// Een afbeeldingsverwijzing (`![alt](hier)`), zoals de serialiser hem
/// schrijft. Geen haakjes of regeleindes in het pad — dat is ook wat Markdown
/// zelf toestaat zonder aanhalingstekens.
final RegExp _imageRef = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)');
final RegExp _backgroundImageLine = RegExp(
  r'^(?:backgroundImage\s*:|\s*<!--\s*_backgroundImage\s*:).+$',
  multiLine: true,
);
final RegExp _cssUrl = RegExp(r'''url\(\s*(['"]?)([^'"\)\n]+)\1\s*\)''');

/// De plaatshouder die in de markdown komt te staan in plaats van het pad.
///
/// Een fragment (`#…`) en geen `data:`-URI ter plekke, om één reden: dedupe.
/// Een achtergrondafbeelding die op veertig dia's staat, zou anders veertig
/// keer als base64 in het bestand belanden. Nu staat elke afbeelding precies
/// één keer in het document en dragen de dia's er een verwijzing naar.
///
/// Een fragment overleeft bovendien DOMPurify ongeschonden — een eigen
/// URI-schema zou eruit gefilterd worden.
const _imagePlaceholder = '#ocideck-img-';

/// Vervangt elke afbeeldingsverwijzing in [markdown] door een plaatshouder, en
/// levert de bijbehorende `data:`-URI's.
///
/// Dit is wat "self-contained" waarmaakt. De README belooft een offline
/// HTML-deck; zonder deze stap wees elke `![…](images/foto.png)` naar een
/// bestand dat de ontvanger niet heeft, en kreeg hij een rij kapotte
/// afbeeldingspictogrammen met de bestandsnamen van de auteur eronder.
///
/// Zonder [resolve] blijft alles staan zoals het stond — dat pad bestaat voor
/// tests en voor aanroepers zonder toegang tot een bestandssysteem.
Future<({String markdown, List<String> dataUris})> _embedImages(
  String markdown,
  HtmlImageResolver? resolve,
  int maxEmbedBytes,
) async {
  const unchanged = <String>[];
  final sources = {
    for (final m in _imageRef.allMatches(markdown)) m.group(2)!.trim(),
    for (final line in _backgroundImageLine.allMatches(markdown))
      for (final url in _cssUrl.allMatches(line.group(0)!))
        url.group(2)!.trim(),
  };
  if (sources.isEmpty) return (markdown: markdown, dataUris: unchanged);

  final index = <String, int>{};
  final uriIndex = <String, int>{};
  final dataUris = <String>[];
  // Cumulatief budget over de héle export. De URI-index telt dezelfde
  // beeldinhoud precies één keer — ook als twee bronpaden ernaar verwijzen of
  // de data:image-URI al in de markdown stond. De grens valt voordat de URI in
  // de uitvoerlijst komt; de resolver begrenst elk extern beeld al per stuk.
  var embeddedBytes = 0;
  for (final source in sources) {
    if (source.isEmpty) continue;
    final uri = source.startsWith('data:image/')
        ? source
        : resolve == null
        ? null
        : await resolve(source);
    if (uri == null || !uri.startsWith('data:image/')) continue;
    final duplicateAt = uriIndex[uri];
    if (duplicateAt != null) {
      index[source] = duplicateAt;
      continue;
    }
    embeddedBytes += uri.length;
    if (embeddedBytes > maxEmbedBytes) {
      throw HtmlEmbedBudgetExceeded(
        usedBytes: embeddedBytes,
        limitBytes: maxEmbedBytes,
      );
    }
    index[source] = dataUris.length;
    uriIndex[uri] = dataUris.length;
    dataUris.add(uri);
  }

  const l10n = AppLocalizations(Locale('nl'));
  final missing = MarpHtmlService._htmlAttr(
    l10n.d('Afbeelding niet ingesloten'),
  );
  var rewritten = markdown.replaceAllMapped(_imageRef, (m) {
    final source = m.group(2)!.trim();
    if (source.isEmpty) return m.group(0)!;
    final at = index[source];
    // Niet in te sluiten: liever een zichtbare melding dan een verwijzing naar
    // een bestand dat de ontvanger niet heeft. Het pad zelf blijft eruit — dat
    // is de map van de auteur, en die hoeft de ontvanger niet te kennen.
    if (at == null) {
      if (resolve == null || source.startsWith('data:')) return m.group(0)!;
      return '<span class="image-missing" role="img" '
          'aria-label="$missing">$missing</span>';
    }
    return '![${m.group(1)}]($_imagePlaceholder$at)';
  });
  rewritten = rewritten.replaceAllMapped(_backgroundImageLine, (line) {
    return line.group(0)!.replaceAllMapped(_cssUrl, (url) {
      final source = url.group(2)!.trim();
      if (source.isEmpty) return url.group(0)!;
      final at = index[source];
      if (at != null) return 'url($_imagePlaceholder$at)';
      return resolve == null || source.startsWith('data:')
          ? url.group(0)!
          : 'none';
    });
  });
  return (markdown: rewritten, dataUris: dataUris);
}

/// Split Marp Markdown into per-slide Markdown chunks: drop the leading YAML
/// front-matter, then break on lines that contain only `---`.
