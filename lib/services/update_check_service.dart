import 'dart:convert';

import '../utils/version_compare.dart';
import 'export_metadata.dart' show kOciDeckVersion;
import 'update_check_fetch.dart';

/// De vaste release-index van de eigen forge. Bewust geen instelling: een
/// versiecheck die naar een vrij instelbare host gaat, is een extra aanvalsvlak
/// (een aanpassing in een instellingenbestand stuurt dan waar de app heen
/// "belt") zonder enig voordeel — de releases staan maar op één plek.
final Uri latestReleaseUri = Uri.parse(
  'https://pawprint.vigilis.online/api/v1/repos/LibreKAT/Ocideck/releases/latest',
);

/// De publieke overzichtspagina die de updatemelding opent. Wordt niet uit het
/// API-antwoord gelezen: een server-leverbaar `html_url`-veld vertrouwen om de
/// browser naartoe te sturen is onnodig — het adres is hier al bekend.
final Uri releasesPageUri = Uri.parse(
  'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases',
);

/// De ophaalstap, injecteerbaar zodat tests hermetisch blijven: de echte
/// implementatie doet DNS + TLS, en een test die daarvan afhangt staat op een
/// verkeerd moment rood. Geeft de responsbody, of `null` bij elke fout.
typedef UpdateCheckFetch = Future<String?> Function(Uri uri);

/// Wat een versiecheck opleverde: de tag die de forge als nieuwste stabiele
/// release kent, plus of die nieuwer is dan het draaiende nummer.
class UpdateCheckResult {
  const UpdateCheckResult({required this.latestVersion, required this.isNewer});

  /// De versie zoals de release-index hem meldt (genormaliseerd, zonder `v`).
  final String latestVersion;

  /// `latestVersion` > `kOciDeckVersion`. `false` betekent niet per se "de
  /// nieuwste": het kan ook "gelijk" of "lokaal vooruit" (een ontwikkelbuild)
  /// zijn — alle drie geen melding waard.
  final bool isNewer;
}

/// Vergelijkt de draaiende versie met de nieuwste release op de forge.
///
/// Elke fout is `null`: geen bereikbaarheid, een 404, kapotte JSON of een
/// raar tag-formaat — allemaal "geen uitspraak", nooit een zichtbare fout.
/// Offline zijn is geen melding waard; de enige uitslag die iets aan de
/// gebruiker mag tonen is "er is een nieuwere versie".
///
/// Het ophalen zelf zit in `update_check_fetch_io.dart` (gepind via NetGuard,
/// redirects uit, byte-kap); de webvariant weigert — de webbouw draait per
/// definitie de gedeployde versie.
class UpdateCheckService {
  const UpdateCheckService({UpdateCheckFetch? fetcher})
    : _fetcher = fetcher ?? defaultUpdateCheckFetch;

  final UpdateCheckFetch _fetcher;

  /// De nieuwste release volgens de forge, of `null` bij elke fout.
  Future<UpdateCheckResult?> fetchLatest() async {
    final body = await _fetcher(latestReleaseUri);
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final tag = decoded['tag_name'];
      if (tag is! String) return null;
      final latest = AppVersion.tryParse(tag);
      if (latest == null) return null;
      return UpdateCheckResult(
        latestVersion: latest.toString(),
        isNewer: AppVersion.isNewer(tag, kOciDeckVersion),
      );
    } on FormatException {
      return null;
    }
  }
}
