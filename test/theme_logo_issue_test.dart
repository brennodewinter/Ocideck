import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/state/theme_logo_provider.dart';

/// `themeLogoIssueFor` is de poort die bepaalt of een stijlprofiel-logo een
/// deckbrede melding oplevert. De renderlaag laat een vertrouwd logo stil
/// vallen — zonder deze melding staat de gebruiker voor een lege hoek zonder
/// te weten waarom (#1298). Hier wordt de beslissing per padsoort vastgepind
/// met nep-predikaten, zodat de asset-manifest en het bestandssysteem buiten
/// de test blijven.
void main() {
  ThemeProfile profile(String? logoPath) =>
      const ThemeProfile().copyWith(logoPath: logoPath);

  SlideQualityIssue? issueFor(
    String? logoPath, {
    bool Function(String) assetExists = _never,
    bool Function(String) fileExists = _never,
  }) => themeLogoIssueFor(
    theme: profile(logoPath),
    projectPath: null,
    bundledAssetExists: assetExists,
    fileExists: fileExists,
  );

  test('geen logo → geen melding', () {
    expect(issueFor(null), isNull);
    expect(issueFor(''), isNull);
    expect(issueFor('   '), isNull);
  });

  test('een `asset:`-sleutel die niet in de bundel zit → melding', () {
    final issue = issueFor('asset:images/ChateauIT_RGB.png');
    expect(issue, isNotNull);
    expect(issue!.kind, SlideQualityIssueKind.themeLogoMissing);
    expect(issue.isDeckWide, isTrue);
    expect(issue.severity, MarkdownValidationSeverity.warning);
    expect(issue.field, 'logoPath');
    expect(issue.args['path'], 'asset:images/ChateauIT_RGB.png');
  });

  test('een `asset:`-sleutel die wél in de bundel zit → geen melding', () {
    expect(
      issueFor(
        'asset:assets/images/librekat-logo.png',
        assetExists: (key) => key == 'assets/images/librekat-logo.png',
      ),
      isNull,
    );
  });

  test('een `mem:`-pad zonder bytes (na een herlaad) → melding', () {
    // WebAssetStore begint leeg in een verse test, dus een mem:-pad wijst
    // nergens heen.
    expect(issueFor('mem:gone-logo.png'), isNotNull);
  });

  test('een bestand dat niet op schijf staat → melding', () {
    final issue = issueFor('/abs/missing.png', fileExists: (_) => false);
    expect(issue, isNotNull);
    expect(issue!.args['path'], '/abs/missing.png');
  });

  test('een bestand dat wél op schijf staat → geen melding', () {
    expect(issueFor('/abs/present.png', fileExists: (_) => true), isNull);
  });

  test('een relatief pad dat niet binnen een project oplost → melding', () {
    // Zonder projectPath lost resolveTrustedAssetPath een relatief pad niet op
    // (null), wat precies het geval is bij een nog niet opgeslagen deck.
    final issue = issueFor('images/logo.png', fileExists: (_) => true);
    expect(issue, isNotNull);
    expect(issue!.args['path'], 'images/logo.png');
  });

  group('themeLogoDarkIssueFor (#1931)', () {
    ThemeProfile darkBgProfile({String? logoPath, String? logoDarkPath}) =>
        ThemeProfile(
          logoPath: logoPath,
          logoDarkPath: logoDarkPath,
          slideBackgroundColor: '#0F172A', // donker
        );

    test('geen logo → geen melding', () {
      expect(themeLogoDarkIssueFor(darkBgProfile()), isNull);
    });

    test(
      'donkere achtergrond + eigen logo zonder donkere variant → melding',
      () {
        final issue = themeLogoDarkIssueFor(
          darkBgProfile(logoPath: '/abs/logo.png'),
        );
        expect(issue, isNotNull);
        expect(issue!.kind, SlideQualityIssueKind.themeLogoDarkMissing);
        expect(issue.isDeckWide, isTrue);
        expect(issue.severity, MarkdownValidationSeverity.warning);
        expect(issue.field, 'logoDarkPath');
      },
    );

    test(
      'donkere achtergrond + eigen logo met donkere variant → geen melding',
      () {
        expect(
          themeLogoDarkIssueFor(
            darkBgProfile(
              logoPath: '/abs/logo.png',
              logoDarkPath: '/abs/logo-dark.png',
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'lichte achtergrond + eigen logo zonder donkere variant → geen melding',
      () {
        expect(
          themeLogoDarkIssueFor(
            ThemeProfile(
              logoPath: '/abs/logo.png',
              slideBackgroundColor: '#FFFFFF',
            ),
          ),
          isNull,
        );
      },
    );

    test('gebundeld merk-logo → geen melding (kiest automatisch)', () {
      expect(
        themeLogoDarkIssueFor(
          ThemeProfile(
            logoPath: 'asset:assets/images/librekat-logo.png',
            slideBackgroundColor: '#0F172A',
          ),
        ),
        isNull,
      );
    });
  });
}

bool _never(String _) => false;
