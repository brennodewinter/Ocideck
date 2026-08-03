import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/openkat_provider.dart';
import '../../../state/settings_provider.dart';
import '../../../theme/app_theme.dart';
import '../../shell/openkat_import_action.dart';
import '../../shell/openkat_import_summary.dart';

/// De instellingen van de OpenKAT-koppeling: de map met rapportages en de knop
/// om ze meteen te controleren. Dit is de *body* van de OpenKAT-sectie op het
/// tabblad Integraties; de schakelaar en de kop eromheen komen van
/// `IntegrationsPanel`, dat per integratie een schakelkaart tekent (#1158).
///
/// Een losse widget en geen `part` van het instellingenvenster (#631): die
/// klasse zit tegen haar plafond, en dit paneel heeft niets van haar nodig —
/// het leest en schrijft alleen `openKatProvider`.
class OpenKatIntegrationBody extends ConsumerWidget {
  const OpenKatIntegrationBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Kies de map waarin OpenKAT de rapportages heeft geplaatst. OciDeck leest deze map alleen; er wordt niets gewijzigd of verstuurd.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 16),
        _DirectoryField(),
        const SizedBox(height: 12),
        const _ImportNowRow(),
        const SizedBox(height: 10),
        Text(
          // Zeg wat er met de map gebeurt vóórdat iemand er een aanwijst. De
          // import leest élk .json-bestand in de map en zijn onderliggende
          // mappen; dat is een ander soort toegang dan "één bestand openen".
          l10n.d(
            'De import leest alleen; er wordt niets in deze map gewijzigd of verstuurd. Bestanden die geen OpenKAT-rapportage blijken, worden overgeslagen en in het importverslag benoemd.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
      ],
    );
  }
}

/// De knop die de import hier meteen uitvoert, met het verslag eronder.
///
/// Waarom hier een knop en niet alleen in het ⋮-menu: dit is de plek waar je
/// de map aanwijst, en wie dat net gedaan heeft wil weten of het werkt. Zonder
/// deze knop is de volgende stap "sluit dit venster en zoek het menu-item op",
/// en dat is precies de stap waarop iemand denkt dat er niets gebeurd is.
///
/// Het venster blijft bewust open staan. Het sluit met Opslaan of Annuleren,
/// en zelf sluiten zou de nog niet opgeslagen instellingen van de andere
/// tabbladen weggooien — dus meldt dit paneel de uitkomst ter plekke in plaats
/// van via een snackbar die achter de dialoog toch niet te lezen is.
class _ImportNowRow extends ConsumerStatefulWidget {
  const _ImportNowRow();

  @override
  ConsumerState<_ImportNowRow> createState() => _ImportNowRowState();
}

class _ImportNowRowState extends ConsumerState<_ImportNowRow> {
  bool _running = false;
  OpenKatImportOutcome? _outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final directory = ref.watch(openKatDirectoryProvider);
    final enabled = directory != null && !_running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          // Een uitgeschakelde knop zegt zelf niet waaróm; zonder map is er
          // niets te importeren.
          message: directory == null ? l10n.d('Geen map gekozen') : '',
          child: FilledButton.icon(
            onPressed: enabled ? _import : null,
            icon: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(l10n.d('Rapportages controleren…')),
          ),
        ),
        if (_outcome != null) ...[
          const SizedBox(height: 8),
          _OutcomeText(outcome: _outcome!),
        ],
      ],
    );
  }

  Future<void> _import() async {
    setState(() {
      _running = true;
      // Het vorige verslag hoort weg vóór de nieuwe run: anders staat er
      // tijdens het draaien een uitkomst die niet meer geldt.
      _outcome = null;
    });
    final outcome = await importOpenKatReports(context, ref, announce: false);
    if (!mounted) return;
    setState(() {
      _running = false;
      _outcome = outcome;
    });
  }
}

/// Het verslag onder de knop: dezelfde zin als de melding uit het menu, plus
/// de wegwijzer waar het resultaat gebleven is — vanuit een dialoog zie je de
/// nieuwe tab er immers niet achter opengaan.
class _OutcomeText extends StatelessWidget {
  final OpenKatImportOutcome outcome;

  const _OutcomeText({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bad = outcome.failed || outcome.loaded == 0;
    final text = [
      openKatImportSummary(l10n, outcome),
      if (!bad && !outcome.updatedDeck)
        l10n.d('Het overzicht staat klaar in een nieuw tabblad.'),
    ].join(' ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          bad ? Icons.error_outline : Icons.check_circle_outline,
          size: 15,
          color: bad ? Theme.of(context).colorScheme.error : AppTheme.slate600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: bad
                  ? Theme.of(context).colorScheme.error
                  : AppTheme.slate600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DirectoryField extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final directory = ref.watch(openKatDirectoryProvider);
    final pathBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      child: Text(
        directory ?? l10n.d('Geen map gekozen'),
        style: TextStyle(
          fontSize: 12,
          color: directory == null ? AppTheme.slate500 : AppTheme.slate800,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
    // Een [Wrap] en geen [Row]: bij 200% interface-tekst passen de kiesknop en de
    // wisknop samen niet meer op één smalle regel, dan valt de wisknop eronder in
    // plaats van de rij te laten overlopen.
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pick(context, ref),
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: Text(l10n.d('Map kiezen…')),
        ),
        if (directory != null)
          IconButton(
            onPressed: () =>
                ref.read(openKatProvider.notifier).setReportDirectory(null),
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.d('Map wissen'),
          ),
      ],
    );
    // De knoppen vallen ónder het padvak zodra de interface-tekst groot of de
    // kolom smal wordt, in plaats van de rij te laten overlopen (dezelfde knik
    // als `_settingFieldRow` in de venster-schil; dit paneel staat buiten die
    // library en draagt hem daarom zelf).
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (scale >= 1.5 || constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pathBox,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: pathBox),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    // Op web bestaat `getDirectoryPath` niet en geeft het stil null terug
    // (#150). De kaart op Uitbreidingen schakelt de module daar al uit, maar
    // een garantie die elders staat verdwijnt bij de eerstvolgende aanroeper.
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    );
    if (result == null) return;
    await ref.read(openKatProvider.notifier).setReportDirectory(result);
  }
}
