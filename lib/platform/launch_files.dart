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
String? deckDeepLinkFrom(Uri uri) {
  final raw = uri.queryParameters['deck']?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}
