import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/doc_link.dart';

void main() {
  // De gecureerde gebundelde set (docs/* + LICENSE.md) zoals in pubspec.yaml.
  const bundled = {
    'docs/USER_GUIDE.md',
    'docs/SHORTCUTS.md',
    'docs/FILE_FORMAT.md',
    'docs/README.md',
    'docs/FAQ.md',
    'docs/TROUBLESHOOTING_GUIDE.md',
    'docs/PRIVACY.md',
    'docs/ACCESSIBILITY.md',
    'docs/KNOWN_LIMITATIONS.md',
    'docs/GLOSSARY.md',
    'docs/LICENSE_COMPLIANCE.md',
    'docs/SBOM.md',
    'docs/PERFORMANCE_GUIDE.md',
    'docs/SECURITY_DESIGN.md',
    'docs/HOSTING.md',
    'docs/MIGRATION_GUIDE.md',
    'LICENSE.md',
  };

  DocLinkTarget? resolve(String href, {String from = 'docs/USER_GUIDE.md'}) =>
      resolveDocLink(
        currentAsset: from,
        href: href,
        bundledAssets: bundled,
        repoTreeUrl: 'https://repo.example/tree/main',
      );

  group('resolveDocLink — extern', () {
    test('https blijft ongewijzigd extern', () {
      expect(
        resolve('https://example.org/pad'),
        const ExternalDocLink('https://example.org/pad'),
      );
    });

    test('mailto is extern', () {
      expect(
        resolve('mailto:security@librekat.nl'),
        const ExternalDocLink('mailto:security@librekat.nl'),
      );
    });

    test('kaal domein (geen schema, geen .md) gaat extern', () {
      expect(resolve('example.org'), const ExternalDocLink('example.org'));
    });

    test('lege href geeft null', () {
      expect(resolve('   '), isNull);
    });
  });

  group('resolveDocLink — ankers', () {
    test('#kopje is een anker binnen hetzelfde document', () {
      expect(resolve('#what-travels'), const SameDocAnchorLink('what-travels'));
    });
  });

  group('resolveDocLink — interne documenten', () {
    test('relatieve .md in dezelfde map opent gebundeld', () {
      expect(
        resolve('FILE_FORMAT.md'),
        const InAppDocLink('docs/FILE_FORMAT.md'),
      );
    });

    test('relatieve .md met anker bewaart het anker', () {
      expect(
        resolve('FILE_FORMAT.md#what-travels-with-the-bundle'),
        const InAppDocLink(
          'docs/FILE_FORMAT.md',
          anchor: 'what-travels-with-the-bundle',
        ),
      );
    });

    test('vanuit LICENSE.md (repo-wortel) naar een gebundeld doc', () {
      expect(
        resolve('docs/PRIVACY.md', from: 'LICENSE.md'),
        const InAppDocLink('docs/PRIVACY.md'),
      );
    });
  });

  group('resolveDocLink — niet-gebundeld valt terug op de repo', () {
    test('een niet-gebundeld doc opent de repo-versie', () {
      expect(
        resolve('BUILD.md'),
        const ExternalDocLink('https://repo.example/tree/main/docs/BUILD.md'),
      );
    });

    test('anker blijft in de repo-URL staan', () {
      expect(
        resolve('BUILD.md#cutting-a-release'),
        const ExternalDocLink(
          'https://repo.example/tree/main/docs/BUILD.md#cutting-a-release',
        ),
      );
    });

    test('../ naar de repo-wortel', () {
      expect(
        resolve('../SECURITY.md'),
        const ExternalDocLink('https://repo.example/tree/main/SECURITY.md'),
      );
    });

    test('geneste map onder docs die niet gebundeld is', () {
      expect(
        resolve('design/GIT_STORAGE.md'),
        const ExternalDocLink(
          'https://repo.example/tree/main/docs/design/GIT_STORAGE.md',
        ),
      );
    });
  });

  group('headingSlug', () {
    test('gewone kop', () {
      expect(headingSlug('Cutting a release'), 'cutting-a-release');
    });

    test('bestaande koppeltekens blijven staan', () {
      expect(headingSlug('make check-conventions'), 'make-check-conventions');
    });

    test('backticks in een kop vallen weg', () {
      expect(headingSlug('`make analyze`'), 'make-analyze');
    });

    test('haakjes vallen weg zonder dubbel koppelteken', () {
      expect(
        headingSlug('Signing the release manifest (minisign)'),
        'signing-the-release-manifest-minisign',
      );
    });

    test('em-streep tussen spaties geeft een dubbel koppelteken', () {
      expect(
        headingSlug('What leaves your device — and only when you ask'),
        'what-leaves-your-device--and-only-when-you-ask',
      );
    });

    test('hoofdletters (macOS) worden kleine letters', () {
      expect(
        headingSlug('Signing and notarising the macOS app'),
        'signing-and-notarising-the-macos-app',
      );
    });
  });

  group('firstHeadingText', () {
    test('haalt de eerste kop-1 op', () {
      expect(
        firstHeadingText('# Bestandsformaat\n\nInhoud'),
        'Bestandsformaat',
      );
    });

    test('herleidt inline-opmaak tot platte tekst', () {
      expect(firstHeadingText('# **Vet** en `code`'), 'Vet en code');
    });

    test('null zonder kop-1', () {
      expect(firstHeadingText('Gewone tekst\n## Sub'), isNull);
    });
  });
}
