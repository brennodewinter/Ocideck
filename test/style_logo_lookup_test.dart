import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/style_logo_lookup.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/content_hash.dart';

import 'import/helpers/docx_styled_fixture.dart';

/// Profielen terugvinden op de inhoud van hun logo. De hash is leidend, niet
/// het pad, en de aanroeper kiest wélk logo telt: dat van de dia of dat van
/// het document.
void main() {
  test('vindt het profiel op de bytes van het gekozen logo', () async {
    final logo = fixtureLogoPng();
    final path = WebAssetStore.put(logo, name: 'logo.png');
    const none = ThemeProfile(name: 'Zonder');
    final withDocumentLogo = ThemeProfile(
      name: 'Document',
      documentLogoPath: path,
    );
    final byDocument = await styleProfilesByLogoHash([
      none,
      withDocumentLogo,
    ], pathOf: (p) => p.effectiveDocumentLogoPath);
    expect(byDocument[sha256Hex(logo)]?.name, 'Document');
    expect(byDocument, hasLength(1));

    // Hetzelfde profiel heeft geen presentatielogo: op dat pad geen treffer.
    final bySlide = await styleProfilesByLogoHash([
      none,
      withDocumentLogo,
    ], pathOf: (p) => p.logoPath);
    expect(bySlide, isEmpty);
  });

  test('een onleesbaar pad en een leeg pad tellen niet', () async {
    final result = await styleProfilesByLogoHash(const [
      ThemeProfile(name: 'Leeg', documentLogoPath: ''),
      ThemeProfile(name: 'Weg', documentLogoPath: 'mem:bestaat-niet'),
    ], pathOf: (p) => p.effectiveDocumentLogoPath);
    expect(result, isEmpty);
  });

  test('bij twee profielen met hetzelfde beeld wint het eerste', () async {
    final logo = fixtureLogoPng(seed: 4);
    final a = WebAssetStore.put(logo, name: 'a.png');
    final b = WebAssetStore.put(logo, name: 'b.png');
    final result = await styleProfilesByLogoHash([
      ThemeProfile(name: 'Eerste', documentLogoPath: a),
      ThemeProfile(name: 'Tweede', documentLogoPath: b),
    ], pathOf: (p) => p.effectiveDocumentLogoPath);
    expect(result[sha256Hex(logo)]?.name, 'Eerste');
  });
}
