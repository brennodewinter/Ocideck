import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Vraagt of de web-import de hele URL naar het eigen fetch-hulppunt mag sturen.
///
/// **Waarom hier een vraag staat en geen automatisme.** Lukt de directe lezing
/// niet — meestal omdat de bronserver geen CORS-headers stuurt — dan kan de
/// webversie terugvallen op een hulppunt op de origin die de app serveert. Dat
/// punt haalt server-zijdig op en krijgt daarmee de volledige URL in handen.
/// Dat is een andere partij dan degene die de gebruiker aanwees, en de URL zelf
/// kan het geheim zijn: een deellink draagt zijn sleutel in het adres.
///
/// De terugval liep automatisch en zonder melding. Nu niet meer: wie niet
/// antwoordt, stuurt niets.
class ProxyFallbackDialog extends StatelessWidget {
  const ProxyFallbackDialog({super.key, required this.host});

  /// De bronhost, zodat de vraag concreet is in plaats van abstract.
  final String host;

  static Future<bool> show(BuildContext context, {required String host}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ProxyFallbackDialog(host: host),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.swap_horiz_outlined),
      title: Text(l10n.d('Via deze website ophalen?')),
      content: Text(
        l10n.d(
          'De server van deze presentatie liet de browser het bestand niet rechtstreeks lezen. OciDeck kan het adres doorgeven aan de website waar OciDeck zelf vandaan komt, en die haalt het dan op. Die website ziet daarmee het volledige adres — staat er een sleutel of code in de link, dan ziet die website die ook.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Doorgaan')),
        ),
      ],
    );
  }
}
