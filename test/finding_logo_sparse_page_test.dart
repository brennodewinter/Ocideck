import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_pagination.dart';

/// #1198: with the default LibreKAT profile (a bottom-left logo, so the finding
/// pagination reserves vertical space for it), a realistic multi-section finding
/// paginated into a HEADER-ONLY page 1 — the header card alone on a mostly-empty
/// slide, its first section pushed to page 2. The cause was a fixed header-card
/// cost that modelled the header at ~80% of a slide; once the logo reserve came
/// off the top of that, no section fit beside the header. With the header cost
/// derived from the (much shorter) real card, page 1 carries its first section
/// again — as it already did without a logo.
void main() {
  const vector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';

  // A realistic first section: a few sentences, the size a pentester writes.
  const description =
      'De inlogpagina geeft de parameter `gebruiker` ongefilterd door aan de '
      'SQL-query, zodat een aanvaller met een enkele quote de query kan '
      'openbreken en de volledige gebruikerstabel kan uitlezen. Dit is '
      'aangetoond met een tijdgebaseerde blinde injectie.';

  FindingSpec realistic() => const FindingSpec(
    heading: 'F-03 · SQL-injectie in het loginformulier',
    scopeObject: 'https://app.voorbeeld/login',
    cvssVector: vector,
    cweId: 89,
    description: description,
    confirmation: 'Bevestigd met sqlmap tegen het test-account.',
    impact: 'Volledige compromittering van de accountgegevens.',
    recommendation: 'Gebruik geparametriseerde queries (prepared statements).',
  );

  List<FindingSpec> renderPages(ThemeProfile? profile) {
    final slide = Slide.create(SlideType.finding).copyWith(
      customMarkdown: realistic().toMarkdown(),
      findingRole: FindingRole.header,
    );
    final pages = expandFindingsForRender([slide], profile: profile);
    return [for (final p in pages) FindingSpec.parse(p.customMarkdown)];
  }

  bool isHeaderOnly(FindingSpec page) =>
      page.description.trim().isEmpty &&
      page.confirmation.trim().isEmpty &&
      page.impact.trim().isEmpty &&
      page.recommendation.trim().isEmpty;

  test('with the LibreKAT logo, page 1 is not a header-only sparse page', () {
    final pages = renderPages(ThemeProfile.libreKat);

    // The finding still paginates (it is genuinely longer than one slide)…
    expect(
      pages.length,
      greaterThan(1),
      reason: 'fixture is meant to overflow one slide',
    );
    // …but page 1 now carries its first section instead of the header alone.
    expect(
      isHeaderOnly(pages.first),
      isFalse,
      reason: 'page 1 must not be a header-only sparse page (#1198)',
    );
    expect(pages.first.description, description);
    // Page 1 keeps the finding's identity (it is the first page).
    expect(pages.first.scopeObject, isNotEmpty);
    expect(pages.first.cvssVector, isNotEmpty);
  });

  test('the logo reserve never produces a header-only page', () {
    // The logo reserve may legitimately cost a page — a finding that only just
    // fit one slide splits once the logo eats ~17% of the height — but it must
    // never do so by stranding the header alone: every page carries content.
    final withLogo = renderPages(ThemeProfile.libreKat);
    for (final page in withLogo) {
      expect(
        isHeaderOnly(page),
        isFalse,
        reason: 'no page may be header-only (#1198)',
      );
    }
    // Page 1 carries the header plus its first section (and, by design, stops
    // there so the header page stays readable rather than crammed).
    expect(withLogo.first.description, isNotEmpty);
  });
}
