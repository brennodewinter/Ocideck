import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';

// Elke hint staat bewust op één regel: de l10n-vertaaltest en de d()-lookup
// werken op de volledige literal, niet op aaneengeschakelde fragmenten.
// ignore_for_file: lines_longer_than_80_chars

/// Korte, gelokaliseerde "wat kan ik hier?"-hint per slidetype. De exhaustieve
/// switch laat de compiler garanderen dat elk [SlideType] een hint heeft —
/// vergeet je er één bij een nieuw type, dan compileert het niet.
String slideTypeHelpText(AppLocalizations l10n, SlideType type) {
  switch (type) {
    case SlideType.title:
      return l10n.d(
        'De openingsslide met een grote titel en ondertitel. Voeg via de afbeeldingsbibliotheek een achtergrondbeeld toe.',
      );
    case SlideType.section:
      return l10n.d(
        'Een tussenkop die een nieuw deel van de presentatie aankondigt. Houd het kort.',
      );
    case SlideType.bullets:
      return l10n.d(
        'Een opsomming. Laat een regel inspringen met spaties voor een subpunt; begin met "[ ]" voor een afvinkbaar item.',
      );
    case SlideType.twoBullets:
      return l10n.d(
        'Twee opsommingskolommen naast elkaar — handig om twee dingen te vergelijken.',
      );
    case SlideType.bulletsImage:
      return l10n.d(
        'Opsomming links, afbeelding rechts. Kies een beeld uit de bibliotheek of sleep het naar binnen.',
      );
    case SlideType.twoImages:
      return l10n.d(
        'Twee afbeeldingen naast elkaar, elk met een eigen bijschrift.',
      );
    case SlideType.image:
      return l10n.d(
        'Eén grote, beeldvullende afbeelding met een optioneel bijschrift.',
      );
    case SlideType.video:
      return l10n.d(
        'Zet begin- en eindtijd in seconden om te knippen, of knip live op het afspeelpunt in het voorbeeld.',
      );
    case SlideType.quote:
      return l10n.d('Een uitgelicht citaat met bronvermelding.');
    case SlideType.table:
      return l10n.d(
        'Plak een selectie uit een spreadsheet met Ctrl/Cmd+V, of typ per cel. Vink "bewerkbaar tijdens presenteren" aan om live te wijzigen.',
      );
    case SlideType.freeMarkdown:
      return l10n.d(
        'Ruwe Markdown met koppen, code, wiskundige LaTeX-formules en mermaid-diagrammen.',
      );
    case SlideType.code:
      return l10n.d(
        'Een codeblok met syntaxiskleuring. Kies de programmeertaal voor de juiste opmaak.',
      );
    case SlideType.chart:
      return l10n.d(
        'Importeer cijfers uit een CSV-bestand of typ ze in het rooster. Kies staaf, lijn, taart of radar.',
      );
    case SlideType.cockpit:
      return l10n.d(
        'Een dashboard van meters. Geef elke meter een waarde, bereik en label.',
      );
    case SlideType.question:
      return l10n.d(
        'Een interactieve quizvraag. Kies het soort (meerkeuze, juist/onjuist, meerdere goed of volgorde) en vul de antwoorden in.',
      );
    case SlideType.timeline:
      return l10n.d(
        'Een tijdlijn van gedateerde gebeurtenissen. Kies de opmaak en hoe de gebeurtenissen verschijnen.',
      );
    case SlideType.scorecard:
      return l10n.d(
        'Een paar kerncijfers met het cijfer van de vorige rapportage ernaast, zodat de verandering het verhaal vertelt. Geef per cijfer aan of stijgen goed of slecht nieuws is.',
      );
    case SlideType.actions:
      return l10n.d(
        'Wat er moet gebeuren, wie het doet en wanneer. Geef per regel aan of het ter informatie is, of dat u een besluit vraagt — dat is waar de zaal op scant.',
      );
    case SlideType.finding:
      return l10n.d(
        'Eén bevinding: onderwerp, CVSS-score, CWE/CVE en de beschrijving, reproductie, impact en aanbeveling.',
      );
    case SlideType.findingsSummary:
      return l10n.d(
        'Managementoverzicht: aantallen bevindingen per ernst, met grafiek en hoofdoorzaken.',
      );
    case SlideType.checklist:
      return l10n.d(
        'Een testlijst volgens een standaard (zoals OWASP WSTG), met status per test en koppeling naar bevindingen.',
      );
    case SlideType.scopeMatrix:
      return l10n.d(
        'Een matrix van scope-objecten tegen standaarden en de mate van toetsing.',
      );
    case SlideType.signOff:
      return l10n.d(
        'De waarheidsverklaring met rapporteur, certificering, handtekening en verzegeling.',
      );
  }
}

/// Uitleg bij de TLP-classificatie van een slide (effect op export/presenteren).
String slideTlpHelpText(AppLocalizations l10n) => l10n.d(
  'De TLP-classificatie bepaalt wie de slide mag zien. Slides met een hoger niveau dan het deck worden bij presenteren en exporteren weggelaten.',
);

/// Subtiele "Wat kan ik hier?"-schakelaar voor de editor-kopregel (naast TYPE
/// en STIJL). De hint zelf verschijnt via [SlideTypeHelpBody], zodat de
/// schakelaar compact op één regel past en de uitleg eronder uitklapt.
class SlideTypeHelpToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;

  const SlideTypeHelpToggle({
    super.key,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 14, color: AppTheme.teal),
            const SizedBox(width: 5),
            Text(
              l10n.d('Wat kan ik hier?'),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 15,
              color: AppTheme.teal,
            ),
          ],
        ),
      ),
    );
  }
}

/// De uitgeklapte hint bij het geselecteerde slidetype (zie
/// [SlideTypeHelpToggle]).
class SlideTypeHelpBody extends StatelessWidget {
  final SlideType type;

  const SlideTypeHelpBody({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      color: AppTheme.paper,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.teal.withValues(alpha: 0.08),
          border: Border.all(color: AppTheme.teal.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                slideTypeHelpText(l10n, type),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppTheme.slate700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
