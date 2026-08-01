import 'package:path/path.dart' as p;

import 'inline_markdown.dart' show stripInlineMarkdown;

/// De repository-boom op de standaardtak. Een niet-gebundeld doc waar een link
/// naar wijst (architectuur, build, `../SECURITY.md`, …) opent hier in de
/// browser — de app draagt maar een gecureerde deelverzameling van `docs/` mee.
const String kRepositoryTreeUrl =
    'https://pawprint.vigilis.online/LibreKAT/Ocideck/src/branch/main';

/// Waar een aangeklikte link in de documentatielezer naartoe leidt. De lezer
/// stuurt élke link door deze classificatie: een interne verwijzing hoort te
/// navigeren, geen `https://FILE_FORMAT.md` te worden die de hostpoort weigert.
sealed class DocLinkTarget {
  const DocLinkTarget();
}

/// Open in de externe browser. Zowel een echt externe link als de repo-versie
/// van een niet-gebundeld doc; `openExternalUrl` bewaakt schema en host.
class ExternalDocLink extends DocLinkTarget {
  const ExternalDocLink(this.url);
  final String url;

  @override
  bool operator ==(Object other) =>
      other is ExternalDocLink && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'ExternalDocLink($url)';
}

/// Open een gebundeld document in de lezer, eventueel scrollend naar [anchor].
class InAppDocLink extends DocLinkTarget {
  const InAppDocLink(this.assetBase, {this.anchor});

  /// Asset-sleutel van het doeldocument, bijv. `docs/FILE_FORMAT.md`.
  final String assetBase;

  /// Kopje-slug om naartoe te scrollen, of null voor de bovenkant.
  final String? anchor;

  @override
  bool operator ==(Object other) =>
      other is InAppDocLink &&
      other.assetBase == assetBase &&
      other.anchor == anchor;
  @override
  int get hashCode => Object.hash(assetBase, anchor);
  @override
  String toString() => 'InAppDocLink($assetBase, anchor: $anchor)';
}

/// Scroll naar een kopje binnen het document dat nu open is (`#kopje`).
class SameDocAnchorLink extends DocLinkTarget {
  const SameDocAnchorLink(this.anchor);
  final String anchor;

  @override
  bool operator ==(Object other) =>
      other is SameDocAnchorLink && other.anchor == anchor;
  @override
  int get hashCode => anchor.hashCode;
  @override
  String toString() => 'SameDocAnchorLink($anchor)';
}

/// Classificeert een aangeklikte link-[href] binnen document [currentAsset].
///
/// - Een link met schema (`http(s):`, `mailto:`) → extern.
/// - `#kopje` → anker binnen ditzelfde document.
/// - Een relatieve `.md`-verwijzing → los ten opzichte van [currentAsset]:
///   staat het resultaat in [bundledAssets], dan opent het in de lezer; anders
///   de repo-versie ([repoTreeUrl]) in de browser.
/// - Al het andere zonder schema (kaal domein, niet-`.md`) → extern, waar
///   `openExternalUrl` het `https://` voorvoegt en de host toetst.
///
/// Zuiver: geen widgets, geen I/O — zo blijft de classificatie volledig
/// toetsbaar los van de lezer. Geeft null voor een lege of zinloze href.
DocLinkTarget? resolveDocLink({
  required String currentAsset,
  required String href,
  required Set<String> bundledAssets,
  String repoTreeUrl = kRepositoryTreeUrl,
}) {
  final raw = href.trim();
  if (raw.isEmpty) return null;

  // Een href die Uri niet kan ontleden is geen interne verwijzing die wij
  // kennen; laat openExternalUrl er het zijne van maken (of stil negeren).
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme) return ExternalDocLink(raw);

  final anchor = uri.hasFragment && uri.fragment.isNotEmpty
      ? uri.fragment
      : null;
  final path = uri.path;

  if (path.isEmpty) {
    return anchor == null ? null : SameDocAnchorLink(anchor);
  }
  if (!path.toLowerCase().endsWith('.md')) return ExternalDocLink(raw);

  final resolved = p.posix.normalize(
    p.posix.join(p.posix.dirname(currentAsset), path),
  );
  if (bundledAssets.contains(resolved)) {
    return InAppDocLink(resolved, anchor: anchor);
  }
  final base = repoTreeUrl.endsWith('/')
      ? repoTreeUrl.substring(0, repoTreeUrl.length - 1)
      : repoTreeUrl;
  return ExternalDocLink('$base/$resolved${anchor == null ? '' : '#$anchor'}');
}

/// De GitHub-stijl anker-slug van een kopje: kleine letters, spaties en
/// bestaande koppeltekens worden `-`, alle overige leestekens vallen weg.
/// Bewust géén samenvoegen of trimmen van koppeltekens — zo levert "… device
/// — and …" net als de bron `device--and` op, zodat de slug de ankers matcht
/// die de docs zelf gebruiken. Inline-opmaak wordt eerst tot platte tekst
/// herleid, zodat backticks en vet in een kopje de slug niet vervuilen.
///
/// Pragmatisch ASCII: niet-ASCII letters (accenten) vallen weg. De gebundelde
/// docs hebben geen ankers naar zulke kopjes, dus dat raakt geen echte link.
String headingSlug(String heading) {
  final plain = stripInlineMarkdown(heading).toLowerCase();
  final buf = StringBuffer();
  for (final unit in plain.codeUnits) {
    final isLower = unit >= 0x61 && unit <= 0x7a; // a–z
    final isDigit = unit >= 0x30 && unit <= 0x39; // 0–9
    final isUnderscore = unit == 0x5f; // _
    if (isLower || isDigit || isUnderscore) {
      buf.writeCharCode(unit);
    } else if (unit == 0x20 || unit == 0x2d) {
      // spatie of koppelteken
      buf.write('-');
    }
  }
  return buf.toString();
}

/// De tekst van het eerste `# `-kopje in [markdown], tot platte tekst herleid —
/// de natuurlijke titel voor een document dat via een link wordt geopend.
/// Null wanneer het document niet met een kop-1 begint.
String? firstHeadingText(String markdown) {
  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('# ')) {
      return stripInlineMarkdown(trimmed.substring(2).trim());
    }
    // Een kop-2+ of andere inhoud vóór een kop-1 betekent dat er geen titel-H1
    // is; stop niet — een document mag met een korte intro beginnen. Maar sla
    // lege regels en gewone tekst over tot we een kop-1 vinden of het einde.
  }
  return null;
}
