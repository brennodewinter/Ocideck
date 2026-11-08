import 'package:path/path.dart' as p;

/// Bestanden waarmee de app is gestart. Op Windows/Linux geeft de
/// bestandsassociatie het pad als commandoregel-argument mee; `main()` vult
/// deze lijst vóór `runApp` en de shell draineert haar bij de eerste frame —
/// het spiegelbeeld van het macOS `ocideck/open_file`-kanaal, dat open-events
/// native aanlevert in plaats van via argumenten.
final List<String> pendingLaunchFiles = [];

/// Of een commandoregel-argument eruitziet als een te openen presentatie-
/// bestand. Bewust een extensie-allowlist: onbekende flags of andere
/// argumenten mogen nooit als bestandspad worden geïnterpreteerd.
bool looksLikeDeckLaunchArg(String arg) {
  final ext = p.extension(arg).toLowerCase();
  return ext == '.md' || ext == '.ocideck' || ext == '.zip';
}

/// De deck-URL uit een web-deeplink (`?deck=<url>`), of null. Los van
/// `Uri.base` zodat de parsing testbaar is; de shell geeft `Uri.base` door.
///
/// `Uri.queryParameters` decodeert elke waarde, dus een correct
/// geëncodeerde bron-URL met een eigen query (`?a=1&b=2`) of fragment
/// (`#kop`) komt hier volledig terug — pas ná dit punt mag de waarde niet
/// meer gecodeerd worden doorgegeven.
String? deckDeepLinkFrom(Uri uri) {
  final raw = uri.queryParameters['deck']?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

/// [uri] zonder de `deck`-queryparameter. De shell roept dit na een
/// geslaagde deeplink-open: de adresbalk weerspiegelt dan wat er open is
/// (OciDeck zelf, niet meer "haal dat bestand"), en een herlading opent
/// niet stil een tweede tabblad met hetzelfde deck (#2826).
Uri withoutDeckParam(Uri uri) {
  final params = Map<String, String>.from(uri.queryParameters)..remove('deck');
  // `replace(queryParameters: {})` laat een kale `?` achter en
  // `queryParameters: null` behoudt hem; herbouwen is de enige weg om de
  // query écht kwijt te zijn wanneer `deck` de laatste parameter was.
  if (params.isEmpty) {
    return Uri(
      scheme: uri.hasScheme ? uri.scheme : null,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.hasAuthority ? uri.host : null,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.isEmpty ? null : uri.path,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }
  return uri.replace(queryParameters: params);
}

/// De deelbare `?deck=`-link voor [deckUrl] op basis van het app-adres
/// [base]. `Uri.replace(queryParameters:)` codeert de waarde correct —
/// ook als de bron zelf een query of fragment draagt; handmatig
/// aaneenrijgen zou precies die gevallen afbreken.
String deckShareLink(Uri base, String deckUrl) {
  return base
      .replace(queryParameters: {'deck': deckUrl}, fragment: null)
      .toString();
}
