import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/marp_compatibility.dart';
import '../../models/presentation_timing.dart';
import '../../l10n/app_localizations.dart';
import '../../services/markdown_service.dart';
import '../../services/marp_compatibility.dart';
import '../../state/deck_provider.dart';
import '../../state/info_safety_provider.dart';
import '../../state/settings_provider.dart';
import '../../models/used_tool.dart';
import '../../services/reference_standards.dart';
import '../../theme/app_theme.dart';
import 'new_deck_dialog.dart' show ThemeProfileSwatch;
import 'settings_dialog.dart';

/// The editable general metadata of a presentation.
class PresentationInfo {
  final String title;
  final String author;
  final String organization;
  final String version;
  final String date;
  final String description;
  final String keywords;

  /// De taal waarin het rapport geschreven wordt (MIAUW EIS 2.3), als taalcode;
  /// leeg = niet vastgelegd.
  final String language;

  /// De standaarden waartegen is getoetst, als `naam@versie` (MIAUW EIS 4.3.2).
  final List<String> standardsUsed;

  /// De hulpmiddelen die bij het onderzoek zijn gebruikt (MIAUW EIS 4.8.2).
  final List<UsedTool> toolsUsed;
  final int presentationTargetSeconds;
  final PresentationTimingConfig presentationTiming;
  final bool showRehearsalSummary;

  /// 'Alleen afspelen'-vergrendeling. Zie [Deck.playOnly].
  final bool playOnly;

  /// Deckbrede acceptatie van Marp-aandachtspunten. Zie
  /// [Deck.marpCompatAccepted].
  final bool marpCompatAccepted;

  /// Naam van het gekozen stijlprofiel (null = ongewijzigd laten).
  final String? styleProfileName;

  const PresentationInfo({
    required this.title,
    required this.author,
    required this.organization,
    required this.version,
    required this.date,
    required this.description,
    required this.keywords,
    required this.language,
    this.standardsUsed = const [],
    this.toolsUsed = const [],
    this.presentationTargetSeconds = 0,
    this.presentationTiming = PresentationTimingConfig.disabled,
    this.showRehearsalSummary = true,
    this.playOnly = false,
    this.marpCompatAccepted = false,
    this.styleProfileName,
  });
}

/// Open de presentatiegegevens en verwerk wat de gebruiker invult.
///
/// Los van de shell, omdat er twee wegen naartoe lopen: het menu-item
/// "Eigenschappen" en een privacybevinding op een frontmatter-veld (auteur,
/// organisatie, trefwoorden). Die tweede weg zit in de kwaliteitsnavigatie en
/// kan niet bij de private shell-methode; zonder deze functie zou hij de
/// verwerking moeten overschrijven, en dan lopen twee kopieën uiteen.
Future<void> editPresentationInfo(BuildContext context, WidgetRef ref) async {
  final deckNotifier = ref.read(deckProvider.notifier);
  final deck = ref.read(deckProvider).deck;
  if (deck == null) return;
  final info = await PresentationInfoDialog.show(context, deck);
  if (info == null) return;
  deckNotifier.updateInfo(
    title: info.title,
    author: info.author,
    organization: info.organization,
    version: info.version,
    date: info.date,
    description: info.description,
    keywords: info.keywords,
    language: info.language,
    standardsUsed: info.standardsUsed,
    toolsUsed: info.toolsUsed,
    presentationTargetSeconds: info.presentationTargetSeconds,
    presentationTiming: info.presentationTiming,
    showRehearsalSummary: info.showRehearsalSummary,
    playOnly: info.playOnly,
    marpCompatAccepted: info.marpCompatAccepted,
  );
  // Een hier gekozen stijlprofiel geldt app-breed (profielen zijn globaal) en
  // wordt meteen op het open deck toegepast.
  final profileName = info.styleProfileName;
  if (profileName == null ||
      profileName == ref.read(deckProvider).deck?.themeProfile.name) {
    return;
  }
  final profile = ref
      .read(settingsProvider)
      .themeProfiles
      .where((p) => p.name == profileName)
      .firstOrNull;
  if (profile == null) return;
  await ref.read(settingsProvider.notifier).selectThemeProfile(profileName);
  deckNotifier.updateThemeProfile(profile);
}

/// Dialog to view and edit a presentation's general metadata (author, version,
/// organization, date, description, keywords). These are stored in the
/// markdown front matter and are therefore also full-text searchable.
class PresentationInfoDialog extends ConsumerStatefulWidget {
  final Deck deck;

  const PresentationInfoDialog({super.key, required this.deck});

  static Future<PresentationInfo?> show(BuildContext context, Deck deck) {
    return showDialog<PresentationInfo>(
      context: context,
      builder: (_) => PresentationInfoDialog(deck: deck),
    );
  }

  @override
  ConsumerState<PresentationInfoDialog> createState() =>
      _PresentationInfoDialogState();
}

class _PresentationInfoDialogState
    extends ConsumerState<PresentationInfoDialog> {
  static const _targetSteps = [
    0,
    300,
    600,
    900,
    1200,
    1500,
    1800,
    2700,
    3600,
    5400,
    7200,
  ];

  /// Sentinel dropdown value for the "custom time" option. When selected the
  /// number of seconds comes from [_customMinutes] instead of a fixed preset.
  static const _customTargetValue = -1;

  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _organization;
  late final TextEditingController _version;
  late final TextEditingController _date;
  late final TextEditingController _description;
  late final TextEditingController _keywords;
  late final TextEditingController _standards;
  late final TextEditingController _tools;
  String _language = '';
  late int _presentationTargetSeconds;
  late PresentationTimingConfig _presentationTiming;
  late final PresentationTimingConfig _initialCustomTiming;
  late bool _useCustomTarget;
  late final TextEditingController _customMinutes;
  late bool _showRehearsalSummary;
  late bool _playOnly;
  late bool _marpCompatAccepted;
  MarpCompatReport? _marpCompat;
  late String _profileName;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.deck.title);
    _author = TextEditingController(text: widget.deck.author);
    _organization = TextEditingController(text: widget.deck.organization);
    _version = TextEditingController(text: widget.deck.version);
    _date = TextEditingController(text: widget.deck.date);
    _description = TextEditingController(text: widget.deck.description);
    _keywords = TextEditingController(text: widget.deck.keywords);
    _standards = TextEditingController(
      text: widget.deck.standardsUsed.join(', '),
    );
    _tools = TextEditingController(
      text: widget.deck.toolsUsed.map((t) => t.format()).join('\n'),
    );
    _language = widget.deck.language;
    _presentationTargetSeconds = widget.deck.presentationTargetSeconds;
    _presentationTiming = widget.deck.presentationTiming;
    _initialCustomTiming = widget.deck.presentationTiming;
    _useCustomTarget =
        _presentationTargetSeconds > 0 &&
        !_targetSteps.contains(_presentationTargetSeconds);
    _customMinutes = TextEditingController(
      text: _useCustomTarget ? '${_presentationTargetSeconds ~/ 60}' : '',
    );
    _showRehearsalSummary = widget.deck.showRehearsalSummary;
    _playOnly = widget.deck.playOnly;
    _marpCompatAccepted = widget.deck.marpCompatAccepted;
    _profileName = widget.deck.themeProfile.name;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _organization.dispose();
    _version.dispose();
    _date.dispose();
    _description.dispose();
    _keywords.dispose();
    _standards.dispose();
    _tools.dispose();
    _customMinutes.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      PresentationInfo(
        title: _title.text.trim(),
        author: _author.text.trim(),
        organization: _organization.text.trim(),
        version: _version.text.trim(),
        date: _date.text.trim(),
        description: _description.text.trim(),
        keywords: _keywords.text.trim(),
        language: _language,
        standardsUsed: _standards.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        toolsUsed: UsedTool.parseAll(_tools.text),
        presentationTargetSeconds: _presentationTargetSeconds,
        presentationTiming: _presentationTiming,
        showRehearsalSummary: _showRehearsalSummary,
        playOnly: _playOnly,
        marpCompatAccepted: _marpCompatAccepted,
        styleProfileName: _profileName,
      ),
    );
  }

  void _setCurrentDate() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    _date.text = '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';
    _date.selection = TextSelection.collapsed(offset: _date.text.length);
  }

  int get _targetDropdownValue =>
      _useCustomTarget ? _customTargetValue : _presentationTargetSeconds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Presentatie-eigenschappen'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _presentationFormatControl(l10n),
                const SizedBox(height: 20),
                _metadataFields(),
                const SizedBox(height: 16),
                _styleProfileControl(l10n),
                const SizedBox(height: 16),
                _targetTimeControl(l10n),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.timeline_outlined, size: 20),
                  title: Text(l10n.d('Tijden-overzicht tonen na afloop')),
                  subtitle: Text(
                    _playOnly
                        ? l10n.d(
                            'Bij een vergrendeld deck verschijnt het overzicht nooit; deze schakelaar doet dan niets.',
                          )
                        : l10n.d(
                            'De tijd per slide wordt altijd gemeten; dit bepaalt alleen of het overzicht na deze presentatie verschijnt.',
                          ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _showRehearsalSummary && !_playOnly,
                  // Uitgeschakeld zodra het deck vergrendeld is: een schakelaar
                  // die aan lijkt te staan maar niets doet, is erger dan geen
                  // schakelaar. De bewaarde waarde blijft ongemoeid, zodat het
                  // ontgrendelen de oude keuze teruggeeft.
                  onChanged: _playOnly
                      ? null
                      : (v) => setState(() => _showRehearsalSummary = v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.lock_outline, size: 20),
                  title: Text(l10n.d('Alleen afspelen (vergrendeld)')),
                  subtitle: Text(
                    l10n.d(
                      'Vergrendelt het deck tot presenteren: de editor, menu\'s en export zijn niet beschikbaar. Uitzetten kan daarna alleen door de sleutel uit het markdown-bestand te halen.',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _playOnly,
                  onChanged: (v) => setState(() => _playOnly = v),
                ),
                const SizedBox(height: 8),
                _marpCompatSection(l10n),
                const SizedBox(height: 8),
                Text(
                  l10n.d(
                    'Deze gegevens worden in de markdown opgeslagen en zijn doorzoekbaar bij het openen.',
                  ),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(onPressed: _save, child: Text(l10n.t('save'))),
        ],
      ),
    );
  }

  /// Marp-compatibiliteit: de huidige status plus de schakelaar waarmee de
  /// auteur aandachtspunten deckbreed accepteert. De sectie ontbreekt helemaal
  /// wanneer de controle uit staat (instelling) — geen grijze tussenstand —
  /// en de schakelaar is alleen zetbaar als er warnings zijn om te accepteren
  /// of om terug te nemen; fouten en een schoon deck zijn niet acceptabel.
  Widget _marpCompatSection(AppLocalizations l10n) {
    // De controle staat uit → hele sectie weg; de bewaarde vlag in het bestand
    // blijft dan bewust ongemoeid. Watch, niet read: de instelling laadt
    // asynchroon en de sectie moet verdwijnen als hij onderweg uitgaat.
    if (!ref.watch(
      settingsProvider.select((s) => s.marpCompatChecksEnabled),
    )) {
      return const SizedBox.shrink();
    }
    final report = _marpCompat ??= MarpCompatibility().check(
      MarkdownService().generateDeck(widget.deck, inlineChartData: true),
      context: !kIsWeb && widget.deck.projectPath != null
          ? MarpCompatContext.project
          : MarpCompatContext.bareFile,
    );
    // De zichtbare status volgt de keuze in deze dialoog mee, zodat de
    // gebruiker vooraf ziet wat opslaan oplevert.
    final effective = switch (report.status) {
      MarpCompatStatus.degraded when _marpCompatAccepted =>
        MarpCompatStatus.accepted,
      MarpCompatStatus.accepted when !_marpCompatAccepted =>
        MarpCompatStatus.degraded,
      _ => report.status,
    };
    final (icon, color, label) = switch (effective) {
      MarpCompatStatus.compatible => (
        Icons.check_circle_outline,
        AppTheme.successFg,
        l10n.d('Marp-compatibel'),
      ),
      MarpCompatStatus.degraded => (
        Icons.warning_amber_outlined,
        AppTheme.warningFg,
        'Marp: ${report.warningCount} ${l10n.d('aandachtspunt(en)')}',
      ),
      MarpCompatStatus.accepted => (
        Icons.task_alt,
        AppTheme.slate600,
        '${l10n.d('Marp-aandachtspunten')} (${report.warningCount}): '
            '${l10n.d('geaccepteerd')}',
      ),
      MarpCompatStatus.incompatible => (
        Icons.error_outline,
        AppTheme.dangerFg,
        '${l10n.d('Niet Marp-compatibel')} — '
            '${report.errorCount} ${l10n.d('fout(en)')}',
      ),
    };
    final canToggle =
        report.status == MarpCompatStatus.degraded ||
        report.status == MarpCompatStatus.accepted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: const Icon(Icons.handshake_outlined, size: 20),
          title: Text(l10n.d('Marp-aandachtspunten geaccepteerd')),
          subtitle: Text(
            canToggle
                ? l10n.d(
                    'Aandachtspunten (zoals inhoud die in andere tools wegvalt) tellen voor dit deck niet als waarschuwing. Wordt in het bestand bewaard.',
                  )
                : report.status == MarpCompatStatus.incompatible
                ? l10n.d(
                    'Fouten zijn niet acceptabel: Marp kan dit deck niet goed weergeven.',
                  )
                : l10n.d('Er is niets om te accepteren.'),
            style: const TextStyle(fontSize: 11),
          ),
          value: canToggle && _marpCompatAccepted,
          onChanged: canToggle
              ? (v) => setState(() => _marpCompatAccepted = v)
              : null,
        ),
      ],
    );
  }

  /// Deckbrede afspeelvorm als drie direct vergelijkbare kaarten. Dit staat
  /// boven de metadata: wie alleen een PechaKucha of Ignite wil maken, hoeft
  /// niet langs auteurs- en rapportvelden te zoeken. Een generieke timing uit
  /// de bron blijft als vierde, huidige kaart zichtbaar zodat openen en
  /// opslaan nooit ongemerkt een geavanceerde instelling wist.
  Widget _presentationFormatControl(AppLocalizations l10n) {
    final hasCustomTiming =
        _initialCustomTiming.hasSettings && !_initialCustomTiming.isTimedPreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_motion_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.d('Presentatievorm'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.d('Kies hoe de dia\'s tijdens het presenteren doorgaan.'),
          style: TextStyle(fontSize: 12, color: AppTheme.slate400),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 560;
            final cards = <Widget>[
              _PresentationFormatCard(
                key: const ValueKey('presentation-format-free'),
                selected: !_presentationTiming.hasSettings,
                icon: Icons.touch_app_outlined,
                title: l10n.d('Vrij presenteren'),
                metric: l10n.d('Zelf doorgaan'),
                description: l10n.d(
                  'Je bepaalt zelf wanneer de volgende dia verschijnt.',
                ),
                onTap: () => setState(
                  () => _presentationTiming = PresentationTimingConfig.disabled,
                ),
              ),
              _PresentationFormatCard(
                key: const ValueKey('presentation-format-pechakucha'),
                selected: _presentationTiming.isPechaKucha,
                icon: Icons.view_carousel_outlined,
                title: l10n.d('PechaKucha'),
                metric: '20 × 20 ${l10n.d('seconden')} · 6:40',
                description: l10n.d('Twintig dia\'s gaan automatisch door.'),
                onTap: () => setState(
                  () => _presentationTiming =
                      const PresentationTimingConfig.pechaKuchaPreset(),
                ),
              ),
              _PresentationFormatCard(
                key: const ValueKey('presentation-format-ignite'),
                selected: _presentationTiming.isIgnite,
                icon: Icons.local_fire_department_outlined,
                title: l10n.d('Ignite'),
                metric: '20 × 15 ${l10n.d('seconden')} · 5:00',
                description: l10n.d('Twintig dia\'s in een stevig tempo.'),
                onTap: () => setState(
                  () => _presentationTiming =
                      const PresentationTimingConfig.ignitePreset(),
                ),
              ),
              if (hasCustomTiming)
                _PresentationFormatCard(
                  key: const ValueKey('presentation-format-custom'),
                  selected:
                      _presentationTiming.hasSettings &&
                      !_presentationTiming.isTimedPreset,
                  icon: Icons.code_outlined,
                  title: l10n.d('Aangepaste timing'),
                  metric: l10n.d('In de bron ingesteld'),
                  description: l10n.d(
                    'Blijft behouden totdat je een andere vorm kiest.',
                  ),
                  onTap: () => setState(
                    () => _presentationTiming = _initialCustomTiming,
                  ),
                ),
            ];
            if (stacked) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i != cards.length - 1) const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1) const SizedBox(width: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// De metadata-invoervelden (titel t/m trefwoorden) van het dialoog.
  Widget _metadataFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_title, 'Titel', 'Titel van de presentatie'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(_author, 'Auteur', 'Bijv. Jan Jansen')),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: _field(_version, 'Versie', 'Bijv. 1.0'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(_organization, 'Organisatie', 'Bijv. Vigilis'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              // Breed genoeg voor tien tekens (JJJJ-MM-DD) plús de suffix-knop:
              // bij 150 viel het laatste dagcijfer achter de knop weg (#1210),
              // precies het cijfer dat de knop leesbaar moest maken.
              width: 184,
              child: _field(
                _date,
                'Datum',
                'Bijv. 2026-05-30',
                onDoubleTap: _setCurrentDate,
                // Een zichtbare knop maakt de dubbelklik-functie vindbaar (#1210):
                // zonder aanwijzing wist niemand dat het veld vandaag kon
                // invullen. Compact, zodat hij het tekstveld niet verdringt.
                suffix: IconButton(
                  icon: const Icon(Icons.today, size: 18),
                  tooltip: context.l10n.d('Vul de datum van vandaag in'),
                  onPressed: _setCurrentDate,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _languageField(),
        const SizedBox(height: 12),
        _field(
          _description,
          'Beschrijving',
          'Korte omschrijving van de presentatie',
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _field(
          _keywords,
          'Trefwoorden',
          'Komma-gescheiden, bijv. kwartaal, cijfers, 2026',
        ),
        // Standaarden en hulpmiddelen zijn MIAUW-vastlegging (EIS 4.3.2/4.8.2).
        // Bij een gewone presentatie zeggen ze niets, dus ze verschijnen pas met
        // de informatieveiligheidsmodule aan — dezelfde lijn als de rest van de
        // module: weglaten, niet grijs maken.
        //
        // Uitzondering: een deck dat de velden al gevuld heeft toont ze hoe dan
        // ook. De waarden overleven een opslagronde sowieso (de controllers
        // worden in initState gevuld en in _save weer uitgelezen), maar
        // ingevulde gegevens onzichtbaar maken leest als dataverlies.
        if (_showMiauwFields) ...[
          const SizedBox(height: 12),
          _standardsField(),
          const SizedBox(height: 12),
          _toolsField(),
        ],
      ],
    );
  }

  /// Of de MIAUW-vastleggingsvelden in beeld horen: module aan, of dit deck
  /// draagt de gegevens al.
  bool get _showMiauwFields =>
      ref.watch(infoSafetyRevealProvider) ||
      widget.deck.standardsUsed.isNotEmpty ||
      widget.deck.toolsUsed.isNotEmpty;

  /// De standaarden waartegen is getoetst (MIAUW EIS 4.3.2).
  ///
  /// Met een knop in het veld die de versies invult die deze build meedraagt.
  /// Dat is een startpunt, geen waarheid: wie tegen een oudere versie heeft
  /// getoetst, past de regel aan. Daarom een tekstveld en geen aanvinklijst —
  /// de vastlegging moet ook standaarden kunnen noemen die OciDeck niet kent.
  ///
  /// De knop zit ín het veld en niet op een eigen regel: deze dialoog is al
  /// dicht en groeide anders voorbij een 800×600-venster.
  Widget _standardsField() => _field(
    _standards,
    'Gebruikte standaarden',
    'Komma-gescheiden, bijv. OWASP WSTG@4.2',
    suffix: IconButton(
      icon: const Icon(Icons.playlist_add, size: 18),
      tooltip: context.l10n.d('Meegeleverde versies invullen'),
      onPressed: _fillCurrentStandards,
    ),
  );

  /// De gebruikte hulpmiddelen (MIAUW EIS 4.8.2), één per regel.
  ///
  /// Een tekstveld en geen rijtjes-editor: dit is een lijst die je één keer per
  /// onderzoek overtikt uit je eigen aantekeningen, niet iets waar je in
  /// rondklikt. De vorm spiegelt die van de standaarden, zodat er één conventie
  /// te onthouden is.
  Widget _toolsField() => _field(
    _tools,
    'Gebruikte hulpmiddelen',
    'Eén per regel, bijv. Burp Suite@2026.4 | https://portswigger.net | Webproxy',
    maxLines: 4,
  );

  void _fillCurrentStandards() {
    setState(() => _standards.text = currentStandardEntries().join(', '));
  }

  /// Stijlprofielkeuze, hier zichtbaar naast de metadata: veel gebruikers
  /// zoeken "de look" bij de presentatie-eigenschappen, niet in instellingen.
  /// De beheerknop opent het instellingen-tabblad Presentatiestijl.
  Widget _styleProfileControl(AppLocalizations l10n) {
    final profiles = ref.watch(settingsProvider.select((s) => s.themeProfiles));
    final value = profiles.any((p) => p.name == _profileName)
        ? _profileName
        : profiles.first.name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.t('styleProfile'),
                  isDense: true,
                  prefixIcon: const Icon(Icons.palette_outlined, size: 18),
                  border: const OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    items: [
                      for (final profile in profiles)
                        DropdownMenuItem(
                          value: profile.name,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ThemeProfileSwatch(profile: profile),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  profile.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (name) {
                      if (name != null) setState(() => _profileName = name);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.d('Stijlprofielen beheren…'),
              icon: const Icon(Icons.tune, size: 18),
              onPressed: () => SettingsDialog.show(
                context,
                initialSection: SettingsSection.presentation,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// De doeltijd-dropdown met toelichting (aftelling in de presenter).
  Widget _targetTimeControl(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.d('Doeltijd (aftellen)'),
            isDense: true,
            prefixIcon: const Icon(Icons.timer_outlined, size: 18),
            border: const OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _targetDropdownValue,
              isExpanded: true,
              isDense: true,
              items: [
                for (final step in _targetSteps)
                  DropdownMenuItem(
                    value: step,
                    child: Text(
                      step == 0
                          ? l10n.d('Geen aftelling')
                          : '${step ~/ 60} ${l10n.d('min')}',
                    ),
                  ),
                DropdownMenuItem(
                  value: _customTargetValue,
                  child: Text(l10n.d('Aangepast…')),
                ),
              ],
              onChanged: (seconds) {
                if (seconds == null) return;
                setState(() {
                  if (seconds == _customTargetValue) {
                    _useCustomTarget = true;
                    // Seed the field from the current value for a smooth switch.
                    final minutes = _presentationTargetSeconds ~/ 60;
                    _customMinutes.text = minutes > 0 ? '$minutes' : '';
                  } else {
                    _useCustomTarget = false;
                    _presentationTargetSeconds = seconds;
                  }
                });
              },
            ),
          ),
        ),
        if (_useCustomTarget)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: 200,
              child: TextField(
                controller: _customMinutes,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: l10n.d('Aangepaste tijd'),
                  suffixText: l10n.d('min'),
                  isDense: true,
                  prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final minutes = int.tryParse(value) ?? 0;
                  setState(
                    () => _presentationTargetSeconds = (minutes * 60).clamp(
                      0,
                      86400,
                    ),
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.d(
              'Doeltijd voor de aftelling in de presenter. Tijdens presenteren fijn af te stellen met de toets K.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
      ],
    );
  }

  /// De taal waarin het rapport geschreven wordt. Een keuzelijst en geen
  /// tekstveld: de waarde is een taalcode die de bevindingskoppen resolvet
  /// (PENTEST_MIAUW §12.3), dus "Nederlands" ingetypt zou niets doen.
  ///
  /// Dit is de taal van het *rapport*, niet van de interface — een Nederlandse
  /// tester schrijft soms een Engels rapport. Vastleggen voldoet MIAUW EIS 2.3.
  /// De taalnamen zijn endoniemen (Nederlands, Deutsch, …) en gaan dus bewust
  /// niet door `d(...)`: zo herkent een lezer zijn eigen taal altijd.
  Widget _languageField() {
    final l10n = context.l10n;
    return DropdownButtonFormField<String>(
      initialValue: _language.isEmpty ? '' : _language,
      isDense: true,
      decoration: InputDecoration(
        labelText: l10n.d('Rapportagetaal'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(value: '', child: Text(l10n.d('Niet vastgelegd'))),
        for (final e in AppLocalizations.languageNames.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) => setState(() => _language = v ?? ''),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    VoidCallback? onDoubleTap,
    Widget? suffix,
  }) {
    final l10n = context.l10n;
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: l10n.d(label),
        hintText: l10n.d(hint),
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
    );
    if (onDoubleTap == null) return field;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: onDoubleTap,
      child: field,
    );
  }
}

class _PresentationFormatCard extends StatelessWidget {
  const _PresentationFormatCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.metric,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String metric;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.46)
        : scheme.surfaceContainerLow;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $metric. $description',
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary.withValues(alpha: 0.14)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: ValueKey(selected),
                        size: 20,
                        color: selected ? scheme.primary : scheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
