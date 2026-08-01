// Part of the file_service library — see file_service.dart.
// Split out for navigability (zelfstandig `.ocideckstyle`-stijlprofiel); all
// imports live in the main library file. Publieke extension:
// buildStyleProfileBytes/exportStyleProfile/importStyleProfileBytes/
// importStyleProfile worden buiten de library aangeroepen (settings_dialog).
part of '../file_service.dart';

/// Herkenningsmarker van een zelfstandig stijlprofiel-bestand. Een import die
/// deze niet ziet weigert het bestand: zonder marker is willekeurige JSON (of
/// een ander OciDeck-bestand) niet te onderscheiden van een profiel.
const _styleProfileMarker = 'style-profile';

/// Versie van het envelope-formaat. Een hoger nummer in een bestand komt uit
/// een nieuwere OciDeck en wordt geweigerd in plaats van half gelezen.
const _styleProfileFormatVersion = 1;

/// Waarom een stijlprofiel-bestand geen profiel opleverde. [cancelled] is een
/// bewuste keuze van de gebruiker (geen melding tonen); de rest verdient uitleg
/// in de UI in plaats van een stil mislukken. Spiegelt [ImageImportFailure].
enum StyleProfileImportFailure {
  cancelled,
  tooLarge,
  invalid,
  unsupportedVersion,
  memoryBudgetExceeded,
}

/// Uitkomst van een import: het [profile] bij succes, anders een [failure].
class StyleProfileImportOutcome {
  final ThemeProfile? profile;
  final StyleProfileImportFailure? failure;

  /// True wanneer het bestand een ingesloten logo droeg dat niet kon worden
  /// teruggezet. Het profiel is dan bruikbaar, maar zonder logo.
  final bool logoOmitted;

  const StyleProfileImportOutcome.success(
    this.profile, {
    this.logoOmitted = false,
  }) : failure = null;

  const StyleProfileImportOutcome.failed(this.failure)
    : profile = null,
      logoOmitted = false;
}

Future<({String? path, bool budgetExceeded})> _materializeStyleLogoSafely(
  Future<String?> Function() materialize,
) async {
  try {
    return (path: await materialize(), budgetExceeded: false);
  } on WebAssetBudgetExceeded catch (e) {
    logWarning('FileService: webgeheugen voor stijllogo vol', e);
    return (path: null, budgetExceeded: true);
  }
}

/// Uitkomst van een export.
class StyleProfileExportOutcome {
  /// False wanneer de gebruiker de opslaan-dialoog afbrak.
  final bool saved;

  /// True wanneer het profiel een eigen logo had dat niet kon worden
  /// ingesloten (bestand weg, of de mem:-store leeg na een herlaad).
  final bool logoOmitted;

  const StyleProfileExportOutcome({
    required this.saved,
    this.logoOmitted = false,
  });
}

/// De bytes van een profielbestand plus of het logo moest worden weggelaten.
class StyleProfileBytes {
  final Uint8List bytes;
  final bool logoOmitted;

  const StyleProfileBytes(this.bytes, {required this.logoOmitted});
}

bool _withinLogoCap(Uint8List? bytes) =>
    bytes != null &&
    bytes.isNotEmpty &&
    bytes.length <= FileService.maxStyleProfileLogoBytes;

/// De ingesloten logo-bytes uit een envelope, of null wanneer er geen zijn of
/// ze niet deugen. Het meegestuurde `mime`-veld wordt genegeerd: het type komt
/// uit de bytes zelf, zodat een bestand geen ander formaat kan voorwenden.
({Uint8List bytes, String mime})? _embeddedLogo(Object? raw) {
  if (raw is! Map) return null;
  final data = raw['data'];
  if (data is! String) return null;
  try {
    final bytes = base64.decode(data);
    if (!_withinLogoCap(bytes)) return null;
    final mime = ImageService.imageMimeFromBytes(bytes);
    if (mime == null) return null;
    return (bytes: bytes, mime: mime);
  } catch (e) {
    logWarning('FileService: ingesloten logo onleesbaar', e);
    return null;
  }
}

extension FileServiceStyleProfile on FileService {
  /// Bestandsnaam-veilige variant van een profielnaam. Eigen sanitizer (net als
  /// `_safeThemeName`): een profielnaam is vrije invoer, dus `/` en `..` moeten
  /// weg voordat hij een pad wordt.
  String _safeProfileFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return cleaned.isEmpty ? 'stijlprofiel' : cleaned;
  }

  /// De bytes achter een eigen logo, of null wanneer ze niet te lezen zijn:
  /// een verdwenen bestand, een lege mem:-store na een herlaad, of te groot.
  /// Ingebouwde `asset:`-logo's komen hier nooit: die reizen als verwijzing.
  Future<Uint8List?> _readLogoBytes(String path, String? projectPath) async {
    try {
      if (WebAssetStore.isMemPath(path)) {
        final bytes = WebAssetStore.bytesFor(path);
        return _withinLogoCap(bytes) ? bytes : null;
      }
      if (kIsWeb) return null; // Geen bestandssysteem.
      // Een logo is vertrouwde stijl-config (geen deck-invoer), dus een
      // absoluut pad buiten de projectmap mag — zie resolveTrustedAssetPath.
      final resolved = resolveTrustedAssetPath(path, projectPath);
      if (resolved == null) return null;
      final file = File(resolved);
      if (!await file.exists()) return null;
      if (await file.length() > FileService.maxStyleProfileLogoBytes) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return _withinLogoCap(bytes) ? bytes : null;
    } catch (e) {
      logWarning('FileService: logo voor stijlprofiel-export onleesbaar', e);
      return null;
    }
  }

  /// Bouw de bytes van een `.ocideckstyle`-bestand: het profiel als JSON in een
  /// envelope met marker en versie.
  ///
  /// Een eigen logo reist als ingesloten base64 mee en `logoPath` gaat leeg het
  /// bestand in — het lokale pad zegt de ontvanger niets en zou de gebruikersnaam
  /// van de afzender lekken. Een ingebouwd `asset:`-logo blijft juist een
  /// verwijzing: elke installatie draagt dezelfde bundel.
  Future<StyleProfileBytes> buildStyleProfileBytes(
    ThemeProfile profile, {
    String? projectPath,
  }) async {
    final json = profile.toJson();
    Map<String, Object?>? logo;
    var logoOmitted = false;

    final path = profile.logoPath?.trim();
    if (path != null && path.isNotEmpty && !isBundledAssetPath(path)) {
      final bytes = await _readLogoBytes(path, projectPath);
      final mime = bytes == null
          ? null
          : ImageService.imageMimeFromBytes(bytes);
      if (bytes != null && mime != null) {
        // `mime` is informatief: de import leidt het type opnieuw uit de bytes
        // af en vertrouwt dit veld niet.
        logo = {'mime': mime, 'data': base64.encode(bytes)};
      } else {
        logoOmitted = true;
      }
      json['logoPath'] = null;
    }

    final envelope = <String, Object?>{
      'ocideck': _styleProfileMarker,
      'version': _styleProfileFormatVersion,
      'profile': json,
      'logo': ?logo,
    };
    return StyleProfileBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      logoOmitted: logoOmitted,
    );
  }

  /// Schrijf [profile] weg als `.ocideckstyle`. Op web biedt de browser het
  /// bestand als download aan; op desktop kiest de gebruiker een bestemming en
  /// schrijven we atomisch (zelfde splitsing als de pakket-export).
  Future<StyleProfileExportOutcome> exportStyleProfile(
    ThemeProfile profile, {
    String? projectPath,
  }) async {
    final built = await buildStyleProfileBytes(
      profile,
      projectPath: projectPath,
    );
    const ext = FileService.styleProfileExtension;
    final name = '${_safeProfileFileName(profile.name)}.$ext';

    if (kIsWeb) {
      await FilePicker.saveFile(fileName: name, bytes: built.bytes);
      return StyleProfileExportOutcome(
        saved: true,
        logoOmitted: built.logoOmitted,
      );
    }
    final dest = await _saveDestination(
      dialogTitle: _d('Stijlprofiel exporteren'),
      fileName: name,
    );
    if (dest == null) {
      return StyleProfileExportOutcome(
        saved: false,
        logoOmitted: built.logoOmitted,
      );
    }
    final target = dest.endsWith('.$ext') ? dest : '$dest.$ext';
    await writeBytesAtomic(File(target), built.bytes);
    return StyleProfileExportOutcome(
      saved: true,
      logoOmitted: built.logoOmitted,
    );
  }

  /// Zet ingesloten logo-bytes terug in opslag en geef het pad dat de renderlaag
  /// aankan; null wanneer dat niet lukte.
  ///
  /// Een `data:`-URI in `logoPath` laten staan werkt niet: geen van de
  /// consumenten (preview, rasterizer, presentator) rendert die. Desktop krijgt
  /// daarom een echt bestand onder de app-support-map — een stijlprofiel is
  /// globaal en moet een herstart overleven. Op web bestaat geen persistente
  /// byte-opslag: daar gaat het logo de in-memory store in en is het ná een
  /// herlaad weg (de rest van het profiel blijft intact).
  Future<String?> _materializeLogo(
    Uint8List bytes,
    String mime,
    String profileName,
    Directory? baseDir,
  ) async {
    final ext = ImageService.extensionForImageMime(mime);
    if (kIsWeb) {
      return WebAssetStore.put(
        bytes,
        name: '${_safeProfileFileName(profileName)}.$ext',
      );
    }
    try {
      final base = baseDir ?? await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'style_logos'));
      await dir.create(recursive: true);
      // Een uuid-naam: twee profielen met dezelfde naam mogen elkaars logo
      // niet overschrijven.
      final target = File(p.join(dir.path, '${const Uuid().v4()}.$ext'));
      await writeBytesAtomic(target, bytes);
      return target.path;
    } catch (e) {
      logWarning('FileService: logo van stijlprofiel niet weggeschreven', e);
      return null;
    }
  }

  /// Lees een `.ocideckstyle`-envelope naar een profiel. Doet géén naam-uniek-
  /// making: dat regelt `saveThemeProfile` al bij het opslaan.
  ///
  /// [logoBaseDir] overschrijft de app-support-map waar een ingesloten logo
  /// belandt (tests), net als `RecoveryService(baseDir:)`.
  Future<StyleProfileImportOutcome> importStyleProfileBytes(
    List<int> bytes, {
    Directory? logoBaseDir,
  }) async {
    if (bytes.isEmpty || bytes.length > FileService.maxStyleProfileBytes) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.tooLarge,
      );
    }
    final Map<String, Object?> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, Object?>) {
        return const StyleProfileImportOutcome.failed(
          StyleProfileImportFailure.invalid,
        );
      }
      envelope = decoded;
    } catch (e) {
      logWarning('FileService: stijlprofiel-bestand onleesbaar', e);
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.invalid,
      );
    }

    if (envelope['ocideck'] != _styleProfileMarker) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.invalid,
      );
    }
    final version = envelope['version'];
    if (version is! num || version > _styleProfileFormatVersion) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.unsupportedVersion,
      );
    }
    final raw = envelope['profile'];
    if (raw is! Map<String, Object?>) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.invalid,
      );
    }

    // fromJson is de gehardende poort: kleuren en lettertypes uit een vreemd
    // bestand komen nooit ongevalideerd in de CSS terecht.
    var profile = ThemeProfile.fromJson(raw);
    var logoOmitted = false;

    final rawLogo = envelope['logo'];
    final embedded = _embeddedLogo(rawLogo);
    if (embedded != null) {
      final materialized = await _materializeStyleLogoSafely(
        () => _materializeLogo(
          embedded.bytes,
          embedded.mime,
          profile.name,
          logoBaseDir,
        ),
      );
      if (materialized.budgetExceeded) {
        return const StyleProfileImportOutcome.failed(
          StyleProfileImportFailure.memoryBudgetExceeded,
        );
      }
      final path = materialized.path;
      profile = path == null
          ? profile.copyWith(clearLogo: true)
          : profile.copyWith(logoPath: path);
      logoOmitted = path == null;
    } else if (rawLogo != null) {
      // Er zat een logo-blok in, maar het is geen bruikbare afbeelding. De rest
      // van het profiel deugt: laat het door zónder logo in plaats van het hele
      // bestand te weigeren.
      profile = profile.copyWith(clearLogo: true);
      logoOmitted = true;
    } else {
      final logoPath = profile.logoPath?.trim();
      // Zonder ingesloten afbeelding is alleen een ingebouwd asset:-logo
      // zinnig; een los pad wijst naar de schijf van de afzender.
      if (logoPath != null &&
          logoPath.isNotEmpty &&
          !isBundledAssetPath(logoPath)) {
        profile = profile.copyWith(clearLogo: true);
      }
    }
    return StyleProfileImportOutcome.success(profile, logoOmitted: logoOmitted);
  }

  /// Kies een `.ocideckstyle`-bestand en lees het uit. `withData` levert op web
  /// én desktop bytes, zodat één pad volstaat (web kent geen bestandspad).
  ///
  /// FileType.any, geen `allowedExtensions`: dat filter grijst de zelfverzonnen
  /// `.ocideckstyle` juist úit op macOS (geen UTI) — zelfde reden als bij
  /// [FileService.pickPackageFile]. [importStyleProfileBytes] toetst daarna de
  /// JSON-envelop met de `ocideck`-marker.
  Future<StyleProfileImportOutcome> importStyleProfile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Stijlprofiel importeren'),
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.cancelled,
      );
    }
    if (file.size > FileService.maxStyleProfileBytes) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.tooLarge,
      );
    }
    final bytes = file.bytes;
    if (bytes == null) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.invalid,
      );
    }
    return importStyleProfileBytes(bytes);
  }
}
