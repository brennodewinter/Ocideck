import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/markdown_validation.dart';
import '../models/settings.dart';
import '../models/slide_quality.dart';
import '../services/web_asset_store.dart';
import '../theme/app_theme.dart';
import '../theme/brand_logo.dart';
import '../utils/bundled_asset.dart';
import '../utils/project_path.dart';
import 'deck_provider.dart';

/// De deckbrede melding voor een stijlprofiel-logo dat niet gevonden wordt, of
/// null als het logo er wel is (of er geen is ingesteld). Puur behalve de
/// meegegeven predikaten, zodat een test de drie padsoorten — `asset:`, `mem:`
/// en een bestand op schijf — kan vastpinnen zonder de asset-manifest of het
/// bestandssysteem aan te spreken.
///
/// Spiegelt de renderbeslissing in [_resolvedImage] (media_previews_image.dart):
/// een vertrouwd logo toont nooit een placeholder, dus een verkeerd pad valt
/// stil. Deze melding is het enige dat de gebruiker dan nog wijst op de oorzaak.
@visibleForTesting
SlideQualityIssue? themeLogoIssueFor({
  required ThemeProfile theme,
  required String? projectPath,
  required bool Function(String assetKey) bundledAssetExists,
  required bool Function(String resolvedPath) fileExists,
}) {
  final path = theme.logoPath?.trim();
  if (path == null || path.isEmpty) return null;

  final missing = switch (path) {
    _ when isBundledAssetPath(path) => !bundledAssetExists(
      bundledAssetKey(path),
    ),
    // Een `mem:`-logo leeft alleen in deze browsersessie; na een herlaad is de
    // store leeg en wijst het pad naar niets.
    _ when WebAssetStore.isMemPath(path) =>
      WebAssetStore.bytesFor(path) == null,
    // Op web bestaat geen bestandssysteem: een bestandspad wijst nooit naar
    // iets. Een profiel-import ruimt zulke paden al op, dus dit treft alleen een
    // pad dat met de hand in de instellingen is gezet — juist daar wil je weten
    // dat het niet werkt.
    _ when kIsWeb => true,
    _ => () {
      final resolved = resolveTrustedAssetPath(path, projectPath);
      return resolved == null || !fileExists(resolved);
    }(),
  };
  if (!missing) return null;

  return SlideQualityIssue(
    slideIndex: kDeckWideSlideIndex,
    kind: SlideQualityIssueKind.themeLogoMissing,
    category: SlideQualityCategory.content,
    severity: MarkdownValidationSeverity.warning,
    field: 'logoPath',
    args: {'path': path},
  );
}

/// Deckbrede waarschuwing wanneer de dia-achtergrond donker is maar het logo
/// geen donkere variant heeft — lichte inkt op een donkere dia is vrijwel
/// onzichtbaar. Geldt alleen voor eigen logo's: een gebundeld merk-logo kiest
/// automatisch zijn donkere variant via [BrandLogo].
@visibleForTesting
SlideQualityIssue? themeLogoDarkIssueFor(ThemeProfile theme) {
  final path = theme.logoPath?.trim();
  if (path == null || path.isEmpty) return null;
  // Gebundeld merk-logo: kiest automatisch, geen waarschuwing nodig.
  if (isBundledAssetPath(path) &&
      BrandLogo.forAssetKey(bundledAssetKey(path)) != null) {
    return null;
  }
  // Donkere variant ingesteld: geen waarschuwing.
  final darkPath = theme.logoDarkPath?.trim();
  if (darkPath != null && darkPath.isNotEmpty) return null;
  // Is de achtergrond donker?
  final bg = AppTheme.parseHexColor(theme.slideBackgroundColor);
  if (bg.computeLuminance() > 0.5) return null; // lichte achtergrond
  return SlideQualityIssue(
    slideIndex: kDeckWideSlideIndex,
    kind: SlideQualityIssueKind.themeLogoDarkMissing,
    category: SlideQualityCategory.content,
    severity: MarkdownValidationSeverity.warning,
    field: 'logoDarkPath',
    args: {'background': theme.slideBackgroundColor},
  );
}

/// De asset-sleutels van de meegebundelde assets, bij de eerste aanvraag uit de
/// asset-manifest geladen en daarna procesbreed bewaard: de bundel verandert
/// niet tijdens een sessie, en deze provider herloopt bij elke deckwijziging.
Set<String>? _bundledAssetKeysCache;

Future<Set<String>> _bundledAssetKeys() async {
  final cached = _bundledAssetKeysCache;
  if (cached != null) return cached;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return _bundledAssetKeysCache = manifest.listAssets().toSet();
}

/// Toetst of het logo van het actieve stijlprofiel gevonden wordt. Exposed als
/// functie zodat hij, net als [computeImageContrastIssues], zowel de globale
/// provider als de per-tab override (in `tab_bar.dart`) kan aansturen.
Future<List<SlideQualityIssue>> computeThemeLogoIssues(Ref ref) async {
  final deck = ref.watch(deckProvider.select((s) => s.deck));
  if (deck == null) return const [];
  final theme = deck.themeProfile;
  final path = theme.logoPath?.trim();
  if (path == null || path.isEmpty) return const [];

  final assetKeys = isBundledAssetPath(path) ? await _bundledAssetKeys() : null;
  final issue = themeLogoIssueFor(
    theme: theme,
    projectPath: deck.projectPath,
    bundledAssetExists: assetKeys?.contains ?? (_) => false,
    fileExists: (resolved) => File(resolved).existsSync(),
  );
  final darkIssue = themeLogoDarkIssueFor(theme);
  return [?issue, ?darkIssue];
}

/// Asynchrone kwaliteitscontrole voor het stijlprofiel-logo. Apart van de
/// synchrone [deckQualityProvider] omdat het opzoeken van een `asset:`-sleutel
/// in de asset-manifest niet inline kan; het paneel en de export-gate mergen
/// de uitkomst. Per tab overriden in `AppShell` (zie `provider_scope_test`).
final themeLogoIssuesProvider = FutureProvider.autoDispose(
  computeThemeLogoIssues,
);
