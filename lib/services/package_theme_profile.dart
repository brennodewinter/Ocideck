import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/settings.dart';
import '../utils/bundled_asset.dart';

/// Wat een `.ocideck`-pakket aan stijl meedraagt: het `theme.json`-lid
/// (#2644). Dezelfde vorm als het thema-record van een OciServe-lespakket —
/// `{name, definition}` — zodat één leesroute beide dekt.
///
/// Het pakket is onbetrouwbare invoer. De profielvelden mogen daarom alleen
/// naar een gebundelde asset of naar een lid bínnen het pakket wijzen; een
/// willekeurig lokaal pad volgen we niet.

/// Ontleed een `theme.json`-lid tot een [ThemeProfile], of null als het lid
/// onleesbaar of incompleet is. De afsluitslide blijft uit: zijn markdown
/// komt niet langs de veiligheidsscan die het deck zelf wel passeert —
/// dezelfde keuze als het OciServe-lesthema.
ThemeProfile? decodePackageThemeProfile(List<int> bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['definition'] is! Map) return null;
  final definition = Map<String, Object?>.from(decoded['definition'] as Map);
  if (decoded['name'] case final String name) definition['name'] = name;
  try {
    return ThemeProfile.fromJson(
      definition,
    ).copyWith(closingSlideEnabled: false);
  } on TypeError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Bouw het `theme.json`-record voor in het pakket. Alleen paden die de
/// ontvanger kan betekenen gaan mee: een gebundelde `asset:`-sleutel of een
/// pakket-relatieve verwijzing. Een absoluut of `mem:`-pad is voor de
/// ontvanger betekenisloos én zou de thuismap van de afzender lekken —
/// precies waarom `.ocideckstyle` zijn `logoPath` leeg schrijft.
ThemeProfile packageProfileForThemeJson(ThemeProfile profile) {
  bool keepable(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty || isBundledAssetPath(v)) return true;
    if (p.isAbsolute(v) ||
        p.windows.isAbsolute(v) ||
        Uri.tryParse(v)?.hasScheme == true) {
      return false;
    }
    return !p.posix.normalize(v.replaceAll('\\', '/')).startsWith('..');
  }

  return profile.copyWith(
    clearLogo: !keepable(profile.logoPath),
    clearLogoDark: !keepable(profile.logoDarkPath),
    clearBrandStrip: !keepable(profile.brandStripPath),
    // '' is "bewust geen documentlogo"; een onbruikbaar pad wordt dat ook,
    // nooit stil het presentatielogo (null).
    documentLogoPath: keepable(profile.documentLogoPath)
        ? profile.documentLogoPath
        : '',
  );
}

/// Herschrijf de vier afbeeldingsvelden van een uit een pakket gelezen
/// profiel via [resolve] — die beslist per verwijzing of hij binnen het
/// pakket/de projectmap valt en geeft dan het runtime-pad (`mem:` of absoluut).
///
/// Een veld dat [resolve] weigert valt weg in plaats van dat er een pad buiten
/// de grens wordt gevolgd. Bij `documentLogoPath` is '' "bewust uit" en
/// `null` "gedeeld met het presentatielogo"; een geweigerde verwijzing wordt
/// uit — niet stil gedeeld.
ThemeProfile resolvePackageProfilePaths(
  ThemeProfile profile, {
  required String? Function(String ref) resolve,
}) {
  (String?, bool) field(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty || isBundledAssetPath(v)) return (raw, false);
    final resolved = resolve(v);
    return resolved == null ? (null, true) : (resolved, false);
  }

  final (logo, dropLogo) = field(profile.logoPath);
  final (dark, dropDark) = field(profile.logoDarkPath);
  final (strip, dropStrip) = field(profile.brandStripPath);
  final (doc, dropDoc) = field(profile.documentLogoPath);
  return profile.copyWith(
    logoPath: logo,
    clearLogo: dropLogo,
    logoDarkPath: dark,
    clearLogoDark: dropDark,
    brandStripPath: strip,
    clearBrandStrip: dropStrip,
    documentLogoPath: dropDoc ? '' : doc,
  );
}
