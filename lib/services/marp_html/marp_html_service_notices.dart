// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out to keep the main library file under the size ceiling: two
// standalone result types (het budgetplafond-exception en de
// derdepartij-notices) die verder los staan van de HTML-bouwer; all imports
// live in the main library file.
part of '../marp_html_service.dart';

/// Gegooid wanneer de ingesloten afbeeldingen samen [kMaxHtmlEmbedTotalBytes]
/// zouden overschrijden. De UI vertaalt dit via `userFacingError`.
class HtmlEmbedBudgetExceeded implements Exception {
  const HtmlEmbedBudgetExceeded({
    required this.usedBytes,
    required this.limitBytes,
  });

  /// Bytes al gereserveerd voor ingesloten afbeeldingen toen de grens viel.
  final int usedBytes;

  /// Het cumulatieve plafond ([kMaxHtmlEmbedTotalBytes], tenzij overschreven).
  final int limitBytes;

  @override
  String toString() =>
      'HtmlEmbedBudgetExceeded(used: $usedBytes, limit: $limitBytes)';
}

/// The third-party notices for one HTML export: a licence banner per inlined
/// script (keyed by npm package name) and the collapsible block that carries the
/// full licence texts.
///
/// Both halves exist because an export makes the *user* the distributing party.
/// MathJax and Mermaid ship minified without any banner at all, so an export
/// used to hand someone 5 MB of third-party code with no way to tell what it
/// was or under what terms — a duty the recipient cannot discharge because we
/// removed the evidence of it.
class ExportNotices {
  const ExportNotices({required this.banners, required this.html});

  /// npm package name → the `/*! @license … */` comment prepended to its
  /// `<script>`, or an empty string for a bundle we have no entry for.
  final Map<String, String> banners;

  /// The `<details>` block appended to `<body>`, with every full licence text.
  final String html;

  String bannerFor(String npm) => banners[npm] ?? '';
}
