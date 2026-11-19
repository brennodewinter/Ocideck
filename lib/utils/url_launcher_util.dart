import 'package:url_launcher/url_launcher.dart';

import 'log.dart';
import 'net_guard.dart';

/// Schemes a deck link may open. Anything else (file:, javascript:, custom app
/// schemes, …) is refused so a deck can't hand the OS a dangerous or
/// unexpected URI.
const _allowedUrlSchemes = {'https', 'http', 'mailto'};

/// De hostpoort voor een `http(s)`-link uit een deck.
///
/// Injecteerbaar voor tests. Productie controleert de bestemmingshost vlak
/// vóór de overdracht aan de browser.
typedef UrlHostGate = Future<bool> Function(String url);

/// Open een link uit slide-tekst in de externe browser. Kale domeinen
/// (zonder schema) krijgen automatisch `https://`. Faalt stil bij ongeldige,
/// niet-openbare of niet-toegestane URLs.
///
/// De hostcontrole geldt voor de URL die aan de browser wordt overgedragen.
/// De browser beheert daarna zelf DNS, omleidingen en zijn eigen sessie.
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
    if (uri.userInfo.isNotEmpty) return;
    final allowed = hostGate == null
        ? NetGuard.isAllowedRemoteUrl(u) &&
              (await NetGuard.resolveConfigured(
                uri.host,
                allowPrivate: false,
              )).isOk
        : await hostGate(u);
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
