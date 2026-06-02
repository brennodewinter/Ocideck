import 'package:url_launcher/url_launcher.dart';

/// Open een link uit slide-tekst in de externe browser. Kale domeinen
/// (zonder schema) krijgen automatisch `https://`. Faalt stil bij ongeldige
/// of niet-openbare URLs.
Future<void> openExternalUrl(String url) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!u.contains('://') && !u.startsWith('mailto:')) {
    u = u.contains('@') ? 'mailto:$u' : 'https://$u';
  }
  final uri = Uri.tryParse(u);
  if (uri == null) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // Nooit de presentatie laten crashen op een kapotte link.
  }
}
