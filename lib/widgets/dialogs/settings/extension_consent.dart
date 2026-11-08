import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/module_registry.dart';
import '../../../services/data_impact_log.dart';

/// Alleen modules met gevolgen voor gegevens vragen om een bewuste keuze.
/// De uitputtende switch dwingt bij een nieuwe module een risicoafweging af.
String? moduleRisk(ModuleId id) => switch (id) {
  ModuleId.ai =>
    'Hulp bij alt-teksten, beschrijvingen en formuleringen. Aanzetten verstuurt nog niets: dat gebeurt pas nadat je zelf een backend hebt gekozen en, bij een clouddienst, uitdrukkelijk hebt bevestigd. Een lokale backend verlaat je computer niet.',
  ModuleId.onlineStorage =>
    'Presentaties openen uit en opslaan naar WebDAV, S3 en git-repository’s, met versiebeheer en samenwerken via een forge. Een deel van deze paden is tot nu toe vooral tegen testomgevingen beproefd; kies dit bewust. Zonder de module werkt alles lokaal gewoon: mappen, bestanden en pakketten.',
  ModuleId.collaboration =>
    'Werk live samen aan een presentatie op een WebDAV-server. Standaard uit. Bewerkingen reizen via een werkmap naast het deck op dezelfde server — zonder versleuteling door OciDeck.',
  ModuleId.videoCalls =>
    'Neem deel aan videovergaderingen en presenteer vanuit OciDeck met een eigen interface: deelnemers naast uw slide, niet in het venster van een andere app. Bring-your-own-server (Jitsi); OciDeck host niets en houdt de gespreksgegevens buiten AI.',
  ModuleId.transcription =>
    'Maak een transcript van een opname of van een bestaand audiobestand — als bewerkbaar Markdown-document, met een duidelijke keuze of het origineel bewaard blijft. Lokaal waar mogelijk; een eigen server alleen als u die kiest.',
  ModuleId.libreplan =>
    'Importeer een projectsnapshot van een LibrePlan-instantie als slides: Gantt, WBS, resourcebelasting, timesheet en meer. Alleen-lezen, op verzoek — er gaat niets naar buiten tot u een server configureert en een import start.',
  ModuleId.forms =>
    'Haal inzendingen van een formulier binnen, houd ze tegen het gepubliceerde formulier en bewaar ze met een register. Een formulier invullen kan ook als dit uit staat. Standaard uit.',
  ModuleId.infoSafety ||
  ModuleId.imports ||
  ModuleId.procesverbetering ||
  ModuleId.assetRights ||
  ModuleId.managementsysteem ||
  ModuleId.elearning => null,
};

const dataImpactWarning =
    'Bij gebruik kunnen persoonsgegevens en bedrijfsinformatie bij de gekozen dienst of ontvangers terechtkomen en bewaard blijven. Controleer toegang en bewaartermijnen. Aanzetten verstuurt nog niets.';

/// Log alleen vaste identificaties en beslissingen, nooit inhoud of adressen.
Future<bool> confirmDataImpact(
  BuildContext context, {
  required String id,
  required String title,
  required String warning,
}) async {
  final l10n = context.l10n;
  await DataImpactLog.record(id, 'shown');
  if (!context.mounted) return false;
  final accepted =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(warning)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Doorgaan')),
            ),
          ],
        ),
      ) ==
      true;
  await DataImpactLog.record(id, accepted ? 'accepted' : 'declined');
  return accepted;
}

ValueChanged<bool> consentToggle(
  BuildContext context,
  ModuleId id,
  ValueChanged<bool> change,
) => (enabled) async {
  final risk = moduleRisk(id);
  if (enabled && risk != null) {
    if (!await confirmDataImpact(
          context,
          id: 'module.${id.name}',
          title: context.l10n.d('Uitbreiding inschakelen?'),
          warning:
              '${context.l10n.d(risk)}\n\n${context.l10n.d(dataImpactWarning)}',
        ) ||
        !context.mounted) {
      return;
    }
  }
  change(enabled);
};
