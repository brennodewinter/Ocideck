import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Third-party components OciDeck ships that are **not** Dart packages.
///
/// Flutter already collects the licence of every resolved package — including
/// the vendored forks under `third_party/` — into the `NOTICES` asset that
/// `showLicensePage` reads. What it does not know about is everything we bundle
/// by hand: the five font families, the YuNet face-detection model, and the
/// five JavaScript/CSS bundles inlined into the offline HTML export.
///
/// Those were shipping without their licence text. That is not a formality:
/// SIL OFL-1.1 §2 lets you redistribute a font *only* if the copyright notice
/// and the licence travel with it, and MIT/BSD/Apache all require the notice to
/// be included in redistributions. The `.txt` files existed in `assets/fonts/`
/// but were never declared in `pubspec.yaml`, so they were not in the binary at
/// all — the app shipped five fonts and a model with no notice whatsoever.
///
/// Registering them here fixes both halves at once: `showLicensePage` gains a
/// section per component, and the asset files are pinned by `pubspec.yaml`, so
/// they are actually in the bundle.
class BundledLicense {
  const BundledLicense({
    required this.component,
    required this.license,
    required this.source,
    required this.licenseAsset,
    this.npm,
  });

  /// Display name, used as the "package" heading in the licence page.
  final String component;

  /// SPDX identifier or expression, as recorded in the SBOM.
  final String license;

  /// Where the component came from, so a reader can check the text themselves.
  final String source;

  /// Bundled asset holding the **full** licence text.
  final String licenseAsset;

  /// npm package name for the bundles listed in
  /// `assets/web_export/MANIFEST.json`, or null for fonts and the model. The
  /// HTML export uses this to pair a manifest entry with its licence text.
  final String? npm;
}

/// The registry of hand-bundled third-party components and their licence texts.
abstract final class BundledLicenses {
  /// Everything that ships inside the application binary.
  static const all = <BundledLicense>[
    BundledLicense(
      component: 'EB Garamond (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/octaviopardo/EBGaramond12',
      licenseAsset: 'assets/fonts/OFL.txt',
    ),
    BundledLicense(
      component: 'Roboto (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/googlefonts/roboto-classic',
      licenseAsset: 'assets/fonts/Roboto-OFL.txt',
    ),
    BundledLicense(
      component: 'Inter (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/rsms/inter',
      licenseAsset: 'assets/fonts/Inter-OFL.txt',
    ),
    BundledLicense(
      component: 'Lora (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/cyrealtype/Lora-Cyrillic',
      licenseAsset: 'assets/fonts/Lora-OFL.txt',
    ),
    BundledLicense(
      component: 'Roboto Mono (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/googlefonts/robotomono',
      licenseAsset: 'assets/fonts/RobotoMono-OFL.txt',
    ),
    BundledLicense(
      component: 'Noto Sans Math (font, subset)',
      license: 'OFL-1.1',
      source: 'https://github.com/notofonts/math',
      licenseAsset: 'assets/fonts/NotoSansMath-OFL.txt',
    ),
    // Same font, registered under the generic `monospace` alias in
    // pubspec.yaml so every `fontFamily: 'monospace'` reference resolves to
    // the bundled file on the CanvasKit web engine (#1784). Listed separately
    // so the licence-page entry matches the family name a user would search
    // for, and so the "every bundled font family has its OFL" test can find it.
    BundledLicense(
      component: 'monospace (font)',
      license: 'OFL-1.1',
      source: 'https://github.com/googlefonts/robotomono',
      licenseAsset: 'assets/fonts/RobotoMono-OFL.txt',
    ),
    BundledLicense(
      component: 'YuNet face-detection model',
      license: 'MIT',
      source:
          'https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet',
      licenseAsset: 'assets/models/YuNet-LICENSE.txt',
    ),
    BundledLicense(
      component: 'marked',
      npm: 'marked',
      license: 'MIT',
      source: 'https://github.com/markedjs/marked',
      licenseAsset: 'assets/licenses/marked-LICENSE.txt',
    ),
    BundledLicense(
      component: 'highlight.js',
      npm: 'highlight.js',
      license: 'BSD-3-Clause',
      source: 'https://github.com/highlightjs/highlight.js',
      licenseAsset: 'assets/licenses/highlight.js-LICENSE.txt',
    ),
    BundledLicense(
      component: 'DOMPurify',
      npm: 'dompurify',
      license: 'Apache-2.0 OR MPL-2.0',
      source: 'https://github.com/cure53/DOMPurify',
      licenseAsset: 'assets/licenses/dompurify-LICENSE.txt',
    ),
    BundledLicense(
      component: 'Mermaid',
      npm: 'mermaid',
      license: 'MIT',
      source: 'https://github.com/mermaid-js/mermaid',
      licenseAsset: 'assets/licenses/mermaid-LICENSE.txt',
    ),
    BundledLicense(
      component: 'MathJax',
      npm: 'mathjax',
      license: 'Apache-2.0',
      source: 'https://github.com/mathjax/MathJax',
      licenseAsset: 'assets/licenses/mathjax-LICENSE.txt',
    ),
  ];

  /// The entry for an npm bundle from `assets/web_export/MANIFEST.json`, or
  /// null when the manifest entry has no npm package (the hash-pinned
  /// highlight.js theme CSS, covered by the highlight.js licence above).
  static BundledLicense? forNpm(String npm) {
    for (final e in all) {
      if (e.npm == npm) return e;
    }
    return null;
  }

  /// Hand the whole set to Flutter's [LicenseRegistry], so `showLicensePage`
  /// lists them next to the packages it collects itself. Call once at startup.
  ///
  /// Registering twice would show every entry twice, so a repeated call is a
  /// no-op — `main()` and a widget test can both call it safely.
  static void register({AssetBundle? bundle}) {
    if (_registered) return;
    _registered = true;
    final source = bundle ?? rootBundle;
    LicenseRegistry.addLicense(() => _entries(source));
  }

  @visibleForTesting
  static void resetForTest() => _registered = false;

  static bool _registered = false;

  static Stream<LicenseEntry> _entries(AssetBundle bundle) async* {
    for (final entry in all) {
      final text = await bundle.loadString(entry.licenseAsset);
      yield LicenseEntryWithLineBreaks(<String>[
        entry.component,
      ], '${entry.component} — ${entry.license}\n${entry.source}\n\n$text');
    }
  }
}
