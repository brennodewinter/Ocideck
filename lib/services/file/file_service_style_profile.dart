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

/// Leesbare JSON (2-spatie indent) voor handmatig bewerkbare `.ocideckstyle`-
/// bestanden. `jsonDecode` aan de import-kant leest zowel compacte als pretty
/// JSON, dus de round-trip blijft heel.
const _styleProfileEncoder = JsonEncoder.withIndent('  ');

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
  /// False wanneer de gebruiker de opslaan-dialoog afbrak — of, op web, wanneer
  /// de browser de download niet aannam. Zie [downloadRefused] voor het
  /// verschil: het eerste is een besluit, het tweede een fout.
  final bool saved;

  /// True wanneer de browser de download weigerde (#1902). Afbreken is stil;
  /// dit hoort de gebruiker te horen, want hij heeft niets afgebroken.
  final bool downloadRefused;

  /// True wanneer het profiel een eigen logo had dat niet kon worden
  /// ingesloten (bestand weg, of de mem:-store leeg na een herlaad).
  final bool logoOmitted;

  const StyleProfileExportOutcome({
    required this.saved,
    this.logoOmitted = false,
    this.downloadRefused = false,
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

/// Leest een door de gebruiker vertrouwd stijllogo voor een render/export.
/// Anders dan documentafbeeldingen mag dit buiten de projectmap staan.
Future<Uint8List?> readStyleLogoBytes(
  String path, {
  String? projectPath,
}) async {
  try {
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      return _withinLogoCap(bytes) ? bytes : null;
    }
    if (kIsWeb) return null;
    final resolved = resolveTrustedAssetPath(path, projectPath);
    if (resolved == null) return null;
    final file = File(resolved);
    if (!await file.exists() ||
        await file.length() > FileService.maxStyleProfileLogoBytes) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return _withinLogoCap(bytes) ? bytes : null;
  } catch (e) {
    logWarning('FileService: logo voor stijlprofiel-export onleesbaar', e);
    return null;
  }
}

Future<({Map<String, Object?>? embedded, bool omitted})> _encodeStyleLogo(
  String? path,
  String? projectPath,
) async {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty || isBundledAssetPath(trimmed)) {
    return (embedded: null, omitted: false);
  }
  final bytes = await readStyleLogoBytes(trimmed, projectPath: projectPath);
  final mime = bytes == null ? null : ImageService.imageMimeFromBytes(bytes);
  return (
    embedded: bytes == null || mime == null
        ? null
        : {'mime': mime, 'data': base64.encode(bytes)},
    omitted: bytes == null || mime == null,
  );
}

Future<String?> _materializeStyleLogo(
  Uint8List bytes,
  String mime,
  String profileName,
  Directory? baseDir,
) async {
  final ext = ImageService.extensionForImageMime(mime);
  if (kIsWeb) {
    return WebAssetStore.put(
      bytes,
      name: '${sanitizeFilename(profileName, fallback: 'stijlprofiel')}.$ext',
    );
  }
  try {
    final base = baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'style_logos'));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, '${const Uuid().v4()}.$ext'));
    await writeBytesAtomic(target, bytes);
    return target.path;
  } catch (e) {
    logWarning('FileService: logo van stijlprofiel niet weggeschreven', e);
    return null;
  }
}

StyleProfileBytes _encodeStyleProfileEnvelope(
  Map<String, Object?> envelope, {
  required bool logoOmitted,
}) {
  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(_styleProfileEncoder.convert(envelope)));

  var bytes = encode();
  if (bytes.length > FileService.maxStyleProfileBytes &&
      envelope.remove('logoDark') != null) {
    (envelope['profile']! as Map<String, Object?>)['logoDarkPath'] = null;
    bytes = encode();
  }
  if (bytes.length > FileService.maxStyleProfileBytes &&
      envelope.remove('documentLogo') != null) {
    (envelope['profile']! as Map<String, Object?>)['documentLogoPath'] = '';
    logoOmitted = true;
    bytes = encode();
  }
  return StyleProfileBytes(bytes, logoOmitted: logoOmitted);
}

extension FileServiceStyleProfile on FileService {
  /// Bestandsnaam-veilige variant van een profielnaam. Gedeelde sanitizer uit
  /// `lib/utils/safe_filename.dart`; een profielnaam is vrije invoer, dus `/`
  /// en `..` moeten weg voordat hij een pad wordt.
  String _safeProfileFileName(String name) =>
      sanitizeFilename(name, fallback: 'stijlprofiel');

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
    final logo = await _encodeStyleLogo(profile.logoPath, projectPath);
    final logoDark = await _encodeStyleLogo(profile.logoDarkPath, projectPath);
    final documentLogo = await _encodeStyleLogo(
      profile.documentLogoPath,
      projectPath,
    );
    if (profile.logoPath?.trim().isNotEmpty == true &&
        !isBundledAssetPath(profile.logoPath!.trim())) {
      json['logoPath'] = null;
    }
    if (profile.logoDarkPath?.trim().isNotEmpty == true &&
        !isBundledAssetPath(profile.logoDarkPath!.trim())) {
      json['logoDarkPath'] = null;
    }
    if (profile.documentLogoPath?.trim().isNotEmpty == true &&
        !isBundledAssetPath(profile.documentLogoPath!.trim())) {
      json['documentLogoPath'] = '';
    }

    final envelope = <String, Object?>{
      'ocideck': _styleProfileMarker,
      'version': _styleProfileFormatVersion,
      'profile': json,
      'logo': ?logo.embedded,
      'logoDark': ?logoDark.embedded,
      'documentLogo': ?documentLogo.embedded,
    };
    return _encodeStyleProfileEnvelope(
      envelope,
      logoOmitted: logo.omitted || logoDark.omitted || documentLogo.omitted,
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

    if (deliversByDownload) {
      final delivered = deliverAsDownload([
        (name: name, bytes: built.bytes),
      ], bundleName: bundleNameFor(name));
      return StyleProfileExportOutcome(
        saved: delivered != null,
        logoOmitted: built.logoOmitted,
        downloadRefused: delivered == null,
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
    final target = withExtension(dest, '.$ext');
    await writeBytesAtomic(File(target), built.bytes);
    return StyleProfileExportOutcome(
      saved: true,
      logoOmitted: built.logoOmitted,
    );
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
      final decoded = jsonDecodeGuarded(utf8.decode(bytes));
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
        () => _materializeStyleLogo(
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

    // Donkere logo-variant: zelfde behandeling als het lichte logo (#1931).
    final rawLogoDark = envelope['logoDark'];
    final embeddedLogoDark = _embeddedLogo(rawLogoDark);
    if (embeddedLogoDark != null) {
      final materializedDark = await _materializeStyleLogoSafely(
        () => _materializeStyleLogo(
          embeddedLogoDark.bytes,
          embeddedLogoDark.mime,
          '${profile.name}-dark',
          logoBaseDir,
        ),
      );
      if (materializedDark.budgetExceeded) {
        return const StyleProfileImportOutcome.failed(
          StyleProfileImportFailure.memoryBudgetExceeded,
        );
      }
      final darkPath = materializedDark.path;
      profile = darkPath == null
          ? profile.copyWith(clearLogoDark: true)
          : profile.copyWith(logoDarkPath: darkPath);
      logoOmitted = logoOmitted || darkPath == null;
    } else if (rawLogoDark != null) {
      profile = profile.copyWith(clearLogoDark: true);
      logoOmitted = true;
    } else {
      final logoDarkPath = profile.logoDarkPath?.trim();
      if (logoDarkPath != null &&
          logoDarkPath.isNotEmpty &&
          !isBundledAssetPath(logoDarkPath)) {
        profile = profile.copyWith(clearLogoDark: true);
      }
    }

    final rawDocumentLogo = envelope['documentLogo'];
    final embeddedDocumentLogo = _embeddedLogo(rawDocumentLogo);
    if (embeddedDocumentLogo != null) {
      final materialized = await _materializeStyleLogoSafely(
        () => _materializeStyleLogo(
          embeddedDocumentLogo.bytes,
          embeddedDocumentLogo.mime,
          '${profile.name}-document',
          logoBaseDir,
        ),
      );
      if (materialized.budgetExceeded) {
        return const StyleProfileImportOutcome.failed(
          StyleProfileImportFailure.memoryBudgetExceeded,
        );
      }
      profile = profile.copyWith(documentLogoPath: materialized.path ?? '');
      logoOmitted = logoOmitted || materialized.path == null;
    } else if (rawDocumentLogo != null) {
      profile = profile.copyWith(documentLogoPath: '');
      logoOmitted = true;
    } else {
      final documentLogoPath = profile.documentLogoPath?.trim();
      if (documentLogoPath != null &&
          documentLogoPath.isNotEmpty &&
          !isBundledAssetPath(documentLogoPath)) {
        profile = profile.copyWith(documentLogoPath: '');
      }
    }
    return StyleProfileImportOutcome.success(profile, logoOmitted: logoOmitted);
  }

  /// Kies een `.ocideckstyle`-bestand en lees het uit. `readAsBytes` levert op
  /// web én desktop bytes, zodat één pad volstaat (web kent geen bestandspad).
  ///
  /// FileType.any, geen `allowedExtensions`: dat filter grijst de zelfverzonnen
  /// `.ocideckstyle` juist úit op macOS (geen UTI) — zelfde reden als bij
  /// [FileService.pickPackageFile]. [importStyleProfileBytes] toetst daarna de
  /// JSON-envelop met de `ocideck`-marker.
  Future<StyleProfileImportOutcome> importStyleProfile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: _d('Stijlprofiel importeren'),
      type: FileType.any,
    );
    if (file == null) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.cancelled,
      );
    }
    if (await file.length() > FileService.maxStyleProfileBytes) {
      return const StyleProfileImportOutcome.failed(
        StyleProfileImportFailure.tooLarge,
      );
    }
    final bytes = await file.readAsBytes();
    return importStyleProfileBytes(bytes);
  }
}
