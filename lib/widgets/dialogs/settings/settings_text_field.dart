import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/secret_store.dart';
import '../../../theme/app_theme.dart';

/// Een invulveld in het instellingenvenster: dezelfde dichtheid, hetzelfde
/// lettertype en dezelfde onderrand als alle andere.
///
/// Het staat hier als gewone widget en niet als helper op de venstertoestand,
/// zodat een paneel dat inloggegevens vraagt buiten de gedeelde `part`-scope
/// kan leven. Zie #631.
class SettingsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final IconData? icon;

  const SettingsTextField(
    this.controller,
    this.label, {
    super.key,
    this.hint,
    this.obscure = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 18),
        ),
      ),
    );
  }
}

/// Het invulveld van een geheim: [SettingsTextField], plus de weigering wanneer
/// dit platform geen sleutelbos heeft.
///
/// Waarom de weigering hier en niet als één melding bovenaan de dialoog: de
/// gebruiker die een token komt invullen, kijkt naar dít veld. Een uitgegrijsd
/// vak zonder tekst laat hem zoeken naar wat hij fout doet; de reden hoort
/// ernaast te staan, op het moment dat hij het probeert.
///
/// Alleen het geheim gaat op slot. Een bron zonder geheim — een openbare URL,
/// een lokaal bestand — blijft op het web gewoon werken, dus de rest van het
/// formulier wordt niet meegenomen in de weigering.
class SettingsSecretField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;

  /// Overschrijft [platformCanStoreSecrets]. Alleen voor tests.
  ///
  /// `kIsWeb` is onder `flutter test` altijd onwaar, dus zonder deze haak zou
  /// juist de tak die een geheim tégenhoudt nooit gedraaid worden — de tak
  /// waar de weigering in zit. [SecretStore] draagt om dezelfde reden dezelfde
  /// haak.
  final bool? canStore;

  const SettingsSecretField(
    this.controller,
    this.label, {
    super.key,
    this.hint,
    this.icon = Icons.key_outlined,
    this.canStore,
  });

  @override
  Widget build(BuildContext context) {
    if (canStore ?? platformCanStoreSecrets) {
      return SettingsTextField(
        controller,
        label,
        hint: hint,
        obscure: true,
        icon: icon,
      );
    }
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            enabled: false,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: label,
              prefixIcon: Icon(icon, size: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppTheme.amber700),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.d('In de browser kan dit niet worden bewaard'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.amber700,
                        ),
                      ),
                      Text(
                        l10n.d(
                          'Een browser heeft geen sleutelbos zoals een computer die heeft: wat OciDeck hier zou opslaan, kan elk script op deze pagina meelezen. Gebruik de desktopversie — daar gaat het geheim wél in de sleutelbos van het besturingssysteem.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
