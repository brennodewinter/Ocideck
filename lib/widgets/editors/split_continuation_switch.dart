import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// De schakelaar "Voortzetting van vorige slide" voor bulletslides.
///
/// Maakt `Slide.continuesSplit` zichtbaar en bedienbaar. Die vlag ontstond als
/// bijproduct van "Splits slide" en was daarna alleen nog in de Markdown terug
/// te vinden of te wijzigen — terwijl hij wél bepaalt hoe groot de tekst wordt
/// weergegeven: pagina's van één reeks delen de grootte van de volste pagina.
/// Een instelling die je opmaak stuurt hoort in de editor te staan, niet alleen
/// in de brontekst.
///
/// De ondertitel noemt dat gevolg met opzet. "Voortzetting van vorige slide"
/// klinkt als een administratief vinkje; dat het je lettergrootte aan de buurman
/// koppelt is de reden dat je hem zou willen uitzetten.
class SplitContinuationSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const SplitContinuationSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.d('Voortzetting van vorige slide')),
      // Eén string-literal, niet twee aaneengeplakte: de l10n-extractor leest
      // de brontekst en ziet bij een gesplitste literal alleen het eerste stuk.
      // ignore: lines_longer_than_80_chars
      subtitle: Text(
        l10n.d(
          'Deze slide hoort bij de lijst van de vorige slide en deelt daarmee één lettergrootte: die van de volste pagina.',
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
