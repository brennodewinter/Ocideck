// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// Het geheim van een netwerkbron: het wachtwoord van Nextcloud, het token van
// git, de API-sleutel van de AI-backend. Die staan niet bij de overige
// instellingen maar versleuteld in de sleutelhanger (D2, §10.1), en dat maakt
// het invulveld lastiger dan het eruitziet.
//
// Twee valkuilen, allebei stil:
//
//  1. Het geheim wordt ná het openen ingeladen, asynchroon. Wie Opslaan indrukt
//     vóórdat die lezing terug is, zou het geheim met een leeg veld
//     overschrijven — je raakt je wachtwoord kwijt zonder dat er iets misgaat
//     op het scherm.
//  2. De sleutelhangersleutel is afgeleid van de *identiteit* van de bron (URL
//     plus gebruiker of eigenaar). Verandert die, dan hoort het geheim mee te
//     verhuizen, ook al is het geheim zelf onveranderd. Gebeurt dat niet, dan
//     staat het onder de oude sleutel en werkt de verbinding niet meer.
//
// Beide worden hier afgehandeld, één keer. De drie bronnen houden verder hun
// eigen vorm — git heeft een forge en een eigenaar, Nextcloud een submap, de
// AI-backend een modus — en dat is met opzet niet in een gedeelde basisklasse
// geperst. Alleen dit stukje boekhouding was letterlijk hetzelfde, en het is
// net het stukje waar een fout duur is.
part of '../settings_dialog.dart';

/// Het invulveld van een geheim, plus wat nodig is om te weten of het écht
/// moet worden weggeschreven.
class KeychainSecret {
  /// Het veld zoals de gebruiker het ziet.
  final TextEditingController field = TextEditingController();

  /// Het geheim zoals het uit de sleutelhanger kwam. Leeg zolang de lezing nog
  /// loopt — en dát is precies waarom [shouldWrite] niet naar leegte kijkt maar
  /// naar verschil.
  String _loaded = '';

  /// De identiteit van de bron bij het openen; de sleutel waaronder het geheim
  /// nu staat.
  String _initialIdentity = '';

  /// Leg vast onder welke identiteit het geheim stond toen het venster opende.
  void rememberIdentity(String identity) => _initialIdentity = identity;

  /// Neem het ingeladen geheim over. Aanroepen wanneer de sleutelhanger
  /// antwoordt; daarna weet [shouldWrite] wat "onveranderd" betekent.
  void adopt(String value) {
    _loaded = value;
    field.text = value;
  }

  /// Of het geheim moet worden weggeschreven onder [identity].
  ///
  /// Twee redenen, en de tweede wordt makkelijk vergeten: het geheim is
  /// gewijzigd, óf de identiteit is gewijzigd en het moet mee naar de nieuwe
  /// sleutel. Is geen van beide waar, dan schrijven we niet — zo kan een snelle
  /// Opslaan de nog-niet-ingeladen waarde niet met leeg overschrijven.
  bool shouldWrite(String identity) =>
      field.text != _loaded || identity != _initialIdentity;

  void dispose() => field.dispose();
}

extension _SettingsSecret on _SettingsDialogState {
  /// Het invulveld van een geheim. De vorm en de weigering op web zitten in
  /// [SettingsSecretField]; dit is de aanroep vanuit de panelen die nog in de
  /// gedeelde scope leven.
  Widget _secretField(
    TextEditingController controller,
    String label, {
    String? hint,
    IconData icon = Icons.key_outlined,
  }) => SettingsSecretField(controller, label, hint: hint, icon: icon);
}
