import 'package:url_launcher/url_launcher.dart';
import 'log.dart';

/// Schemes a deck link may open. Anything else (file:, javascript:, custom app
/// schemes, …) is refused so a deck can't hand the OS a dangerous or
/// unexpected URI.
const _allowedUrlSchemes = {'https', 'http', 'mailto'};

/// Open een link uit slide-tekst in de externe browser. Kale domeinen
/// (zonder schema) krijgen automatisch `https://`. Faalt stil bij ongeldige,
/// niet-openbare of niet-toegestane URLs.
Future<void> openExternalUrl(String url) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!u.contains('://') && !u.startsWith('mailto:')) {
    u = u.contains('@') ? 'mailto:$u' : 'https://$u';
  }
  final uri = Uri.tryParse(u);
  if (uri == null) return;
  if (!_allowedUrlSchemes.contains(uri.scheme.toLowerCase())) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    logWarning('openExternalUrl: launching external URL failed', e);
    // Nooit de presentatie laten crashen op een kapotte link.
  }
}
