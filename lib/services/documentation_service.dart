import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Loads bundled Markdown documentation for the in-app reader.
///
/// Documents are shipped as assets under `docs/` (plus the root `LICENSE.md`).
/// Loading is **locale-aware and forward-looking**: for language `xx` it prefers
/// a translated variant `docs/NAME.xx.md` when one is bundled, and otherwise
/// falls back to the source document `docs/NAME.md`. So translated docs can be
/// added later — drop `docs/USER_GUIDE.de.md` in and declare it in
/// `pubspec.yaml` — without touching any calling code.
///
/// A leading HTML/SPDX comment header (as `LICENSE.md` carries) is stripped so
/// it doesn't show up as literal text at the top of the reader.
class DocumentationService {
  const DocumentationService();

  /// Loads [baseAsset] (e.g. `docs/USER_GUIDE.md` or `LICENSE.md`), preferring a
  /// `.<languageCode>.md` sibling when it is bundled. `nl` and unknown codes use
  /// the base document.
  Future<String> load(String baseAsset, String languageCode) async =>
      (await loadDetailed(baseAsset, languageCode)).text;

  /// Hetzelfde, plus of dit de basisversie is in plaats van een vertaling.
  ///
  /// De lezer heeft dat nodig om het te kúnnen zeggen. Alle 24 gebundelde
  /// documenten bestaan alleen in het Engels, terwijl hun titels in 32 talen
  /// staan — dus wie de app op Pools zet, ziet een Poolse titel en krijgt
  /// Engels. De machinerie voor een `.pl.md` ernaast is er al; wat ontbrak was
  /// dat het scherm er iets over zei (#626).
  Future<({String text, bool isBaseVersion})> loadDetailed(
    String baseAsset,
    String languageCode,
  ) async {
    final key = await _resolveKey(baseAsset, languageCode);
    final raw = await rootBundle.loadString(key);
    return (text: _stripLeadingComment(raw), isBaseVersion: key == baseAsset);
  }

  /// Picks the localized variant key when it exists in the asset manifest,
  /// otherwise the base key. Uses the manifest (not a load-and-catch) so a
  /// missing variant is never an error path.
  Future<String> _resolveKey(String baseAsset, String languageCode) async {
    if (languageCode == 'nl' || languageCode.isEmpty) return baseAsset;
    final variant = _variantKey(baseAsset, languageCode);
    if (variant == baseAsset) return baseAsset;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().contains(variant) ? variant : baseAsset;
  }

  /// `docs/USER_GUIDE.md` + `de` → `docs/USER_GUIDE.de.md`.
  static String _variantKey(String baseAsset, String languageCode) {
    final dot = baseAsset.lastIndexOf('.');
    if (dot <= 0) return baseAsset;
    return '${baseAsset.substring(0, dot)}.$languageCode${baseAsset.substring(dot)}';
  }

  /// Drops a single leading `<!-- … -->` comment block and surrounding blank
  /// lines, so files with an SPDX/licence header start at their first heading.
  static String _stripLeadingComment(String raw) {
    final text = raw.trimLeft();
    if (!text.startsWith('<!--')) return raw.trim();
    final end = text.indexOf('-->');
    if (end < 0) return raw.trim();
    return text.substring(end + 3).trim();
  }
}
