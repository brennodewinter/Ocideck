import 'package:flutter/widgets.dart';

/// Een tekstveldcontroller die zijn *bewerkings*luisteraars alleen wekt wanneer
/// de tekst werkelijk verandert.
///
/// Een gewone [TextEditingController] meldt élke wijziging van zijn waarde — en
/// de cursorpositie zit in diezelfde waarde. Eén klik in een veld is dus net zo
/// goed een melding als een aanslag, en dat geldt ook voor de focus die
/// terugkomt nadat een systeemvenster sluit. De dia-editors lazen zo'n melding
/// als een bewerking en schreven een ongewijzigde dia terug naar het deck. Het
/// gevolg was drieledig: de presentatie heette 'gewijzigd' terwijl er niets
/// veranderde, ongedaan-maken kreeg een stap die niets terugdraait, en de
/// niet-opgeslagen-stip kwam meteen ná het opslaan weer op — bij het opslaan
/// van een nieuw deck zelfs zónder tussenklik, omdat het bewaarvenster de focus
/// weghaalt en teruggeeft terwijl er geschreven wordt.
///
/// [addListener] blijft ongefilterd: het tekstveld zelf moet juist wél van elke
/// cursorwissel weten, anders beweegt de cursor niet mee op het scherm. Alleen
/// wie [addTextListener] gebruikt, krijgt de stroom zonder cursorruis.
class EditorTextController extends TextEditingController {
  EditorTextController({super.text}) : _lastText = text ?? '' {
    super.addListener(_dispatchTextChange);
  }

  String _lastText;
  final List<VoidCallback> _textListeners = [];

  /// Meld [listener] aan voor echte tekstwijzigingen. Tegenhanger van
  /// [addListener], dat óók bij een cursorwissel afgaat.
  void addTextListener(VoidCallback listener) => _textListeners.add(listener);

  /// Meld [listener] weer af. Editors die hun velden tussentijds opnieuw
  /// opbouwen (een opsomming die groeit of krimpt) doen dit vóór het opruimen.
  void removeTextListener(VoidCallback listener) =>
      _textListeners.remove(listener);

  void _dispatchTextChange() {
    if (text == _lastText) return;
    _lastText = text;
    // Kopie: een luisteraar mag zichzelf tijdens de melding afmelden.
    for (final listener in List<VoidCallback>.of(_textListeners)) {
      listener();
    }
  }

  @override
  void dispose() {
    _textListeners.clear();
    super.dispose();
  }
}
