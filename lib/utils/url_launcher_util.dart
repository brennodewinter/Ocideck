import 'package:url_launcher/url_launcher.dart';

import 'log.dart';
import 'net_guard.dart';

/// Schemes a deck link may open. Anything else (file:, javascript:, custom app
/// schemes, …) is refused so a deck can't hand the OS a dangerous or
/// unexpected URI.
const _allowedUrlSchemes = {'https', 'http', 'mailto'};

/// De hostpoort voor een `http(s)`-link uit een deck.
///
/// Standaard [NetGuard.isAllowedMediaUrlResolved] — dezelfde poort waar een
/// deck-afbeelding en een deck-video al doorheen gaan. Injecteerbaar zodat de
/// tests hermetisch blijven: de echte poort doet een DNS-opzoeking, en een test
/// die van het netwerk afhangt staat op een verkeerd moment rood.
typedef UrlHostGate = Future<bool> Function(String url);

/// Open een link uit slide-tekst in de externe browser. Kale domeinen
/// (zonder schema) krijgen automatisch `https://`. Faalt stil bij ongeldige,
/// niet-openbare of niet-toegestane URLs.
///
/// **De hostpoort is waarom dit niet zomaar `launchUrl` is.** Een link in een
/// deck is invoer, geen instructie, en dit was de enige deck-gestuurde host die
/// NetGuard oversloeg: `http://169.254.169.254/` of een adres op het thuisnetwerk
/// van de lezer opende gewoon, in zijn browser, mét zijn cookies. Elke andere
/// deck-gestuurde verbinding — afbeelding, video, import — ging al door dezelfde
/// poort; deze hoorde daar niet buiten te vallen. De regel hierboven beloofde
/// "niet-openbare" URLs trouwens al te weigeren; nu doet de code dat ook.
///
/// `mailto:` slaat de hostpoort over: daar zit geen host in, en de mailclient
/// legt geen verbinding met een adres dat het deck aanwijst.
Future<void> openExternalUrl(String url, {UrlHostGate? hostGate}) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!u.contains('://') && !u.startsWith('mailto:')) {
    u = u.contains('@') ? 'mailto:$u' : 'https://$u';
  }
  final uri = Uri.tryParse(u);
  if (uri == null) return;
  final scheme = uri.scheme.toLowerCase();
  if (!_allowedUrlSchemes.contains(scheme)) return;
  if (scheme != 'mailto') {
    final allowed = await (hostGate ?? NetGuard.isAllowedMediaUrlResolved)(u);
    if (!allowed) {
      // Bewust zonder het adres: een deck-URL kan zelf een gegeven zijn.
      logWarning('openExternalUrl: host geweigerd door NetGuard');
      return;
    }
  }
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    logWarning('openExternalUrl: launching external URL failed', e);
    // Nooit de presentatie laten crashen op een kapotte link.
  }
}
