// Part of the editor_panel library — see editor_panel.dart.
// Split out for navigability (toolbar & per-slide controls); all imports live in the main
// library file. These top-level widgets relocate verbatim — no behaviour change.
part of 'editor_panel.dart';

class _EditorToolbar extends StatelessWidget {
  final Slide slide;
  final List<ThemeProfile> profiles;
  final ThemeProfile activeProfile;
  final ThemeProfile defaultProfile;
  final ValueChanged<SlideType> onTypeChanged;
  final ValueChanged<ThemeProfile> onProfileChanged;
  final VoidCallback onDefaultProfileRequested;

  /// Of de informatieveiligheid-module onthuld is; gate de security-slidetypes
  /// in de kiezer net als 'Slide toevoegen' (zie [AddSlideDialog]).
  final bool revealInfoSafety;

  /// Of de Procesverbetering-module onthuld is.
  final bool revealProcesverbetering;

  /// Of de Managementsysteem-module onthuld is.
  final bool revealManagementsysteem;

  /// Of de eLearning-module onthuld is (#1999).
  final bool revealElearning;

  /// Extra items rechts in de kopregel (bijv. de hulp-toggle en de
  /// kwaliteits-samenvatting), zodat die op dezelfde regel als TYPE/STIJL staan.
  final List<Widget> trailing;

  const _EditorToolbar({
    required this.slide,
    required this.profiles,
    required this.activeProfile,
    required this.defaultProfile,
    required this.onTypeChanged,
    required this.onProfileChanged,
    required this.onDefaultProfileRequested,
    required this.revealInfoSafety,
    this.revealProcesverbetering = false,
    this.revealManagementsysteem = false,
    this.revealElearning = false,
    this.trailing = const [],
  });

  /// Open dezelfde visuele kiezer als 'Slide toevoegen' om het slide-type te
  /// wijzigen. Is de huidige slide al een module-type, dan tonen we die
  /// categorie óók als de module uit staat — anders zit je vast en kun je
  /// zo'n slide niet naar een ander type in dezelfde categorie ombouwen.
  Future<void> _pickType(BuildContext context) async {
    final revealSec =
        revealInfoSafety ||
        slide.type.category == SlideCategory.informationSecurity;
    final revealImp =
        revealProcesverbetering ||
        slide.type.category == SlideCategory.procesverbetering;
    // Revealed when the module switch is on, or the current slide already is a
    // controlStatus slide so it can be retyped within its own category.
    final revealMgmt =
        revealManagementsysteem ||
        slide.type.category == SlideCategory.managementsysteem;
    final revealElearn =
        revealElearning || slide.type.category == SlideCategory.eLearning;
    final picked = await AddSlideDialog.show(
      context,
      revealInfoSafety: revealSec,
      revealProcesverbetering: revealImp,
      revealManagementsysteem: revealMgmt,
      revealElearning: revealElearn,
    );
    if (picked != null && picked != slide.type) onTypeChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    // Make sure the active profile is always selectable, even when it was
    // loaded from a file and is not part of the saved profile list.
    final profileItems = <ThemeProfile>[
      ...profiles,
      if (!profiles.any((p) => p.name == activeProfile.name)) activeProfile,
    ];

    final fields = <Widget>[
      Expanded(
        child: _ToolbarField(
          label: 'TYPE',
          child: _SlideTypePickerButton(
            type: slide.type,
            onTap: () => _pickType(context),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _ToolbarField(
          label: 'STIJL',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: activeProfile.name,
              isExpanded: true,
              isDense: true,
              borderRadius: BorderRadius.circular(6),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.tealFg,
                fontWeight: FontWeight.w600,
              ),
              items: [
                for (final profile in profileItems)
                  DropdownMenuItem(
                    value: profile.name,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          size: 14,
                          color: AppTheme.tealFg,
                        ),
                        const SizedBox(width: 4),
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
                if (name == null) return;
                final profile = profileItems.firstWhere(
                  (p) => p.name == name,
                  orElse: () => activeProfile,
                );
                onProfileChanged(profile);
              },
            ),
          ),
        ),
      ),
      // Alleen tonen wanneer de stijl afwijkt van de standaard — anders
      // voegt het niets toe. Eén klik zet 'm terug op het standaardprofiel.
      if (activeProfile.name != defaultProfile.name) ...[
        const SizedBox(width: 2),
        IconButton(
          tooltip:
              '${context.l10n.d('Terug naar standaardstijl')} ${defaultProfile.name}',
          onPressed: onDefaultProfileRequested,
          icon: const Icon(Icons.restart_alt, size: 16),
          color: AppTheme.tealFg,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    ];

    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Onder deze breedte passen de TYPE/STIJL-velden en de trailing-chips
          // (hulp, kwaliteit, Bron, split) niet meer naast elkaar zonder de
          // Expanded-velden tot niets te pletten; dan stapelen we de trailing
          // eronder. De grens ligt boven de smalle-paneelbreedte (~680) sinds
          // de 'Bron'-chip (#1160) de trailing-groep breder maakte.
          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: fields),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.end,
                  runSpacing: 4,
                  children: trailing,
                ),
              ],
            );
          }
          return Row(children: [...fields, ...trailing]);
        },
      ),
    );
  }
}

/// De editor-kopregel: TYPE- en STIJL-keuze plus de compacte schakelaars voor
/// hulp en slidekwaliteit op één regel. Elke schakelaar klapt z'n inhoud
/// eronder uit (elk beheert z'n eigen open/dicht-toestand). De slide-specifieke
/// instellingen staan niet meer hier maar als inklapbaar blok onder de inhoud
/// (zie [_SlideSettingsSection]).
class _EditorHeaderBar extends StatefulWidget {
  final Slide slide;
  final List<ThemeProfile> profiles;
  final ThemeProfile activeProfile;
  final ThemeProfile defaultProfile;
  final ValueChanged<SlideType> onTypeChanged;
  final ValueChanged<ThemeProfile> onProfileChanged;
  final VoidCallback onDefaultProfileRequested;

  /// Opent de rauwe markdown-bron van de actieve dia (de schakelaar uit #1160).
  final VoidCallback onOpenSource;
  final bool revealInfoSafety;
  final bool revealProcesverbetering;
  final bool revealManagementsysteem;
  final bool revealElearning;

  const _EditorHeaderBar({
    required this.slide,
    required this.profiles,
    required this.activeProfile,
    required this.defaultProfile,
    required this.onTypeChanged,
    required this.onProfileChanged,
    required this.onDefaultProfileRequested,
    required this.onOpenSource,
    required this.revealInfoSafety,
    this.revealProcesverbetering = false,
    this.revealManagementsysteem = false,
    this.revealElearning = false,
  });

  @override
  State<_EditorHeaderBar> createState() => _EditorHeaderBarState();
}

class _EditorHeaderBarState extends State<_EditorHeaderBar> {
  bool _helpOpen = false;
  bool _qualityOpen = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorToolbar(
          slide: widget.slide,
          profiles: widget.profiles,
          activeProfile: widget.activeProfile,
          defaultProfile: widget.defaultProfile,
          onTypeChanged: widget.onTypeChanged,
          onProfileChanged: widget.onProfileChanged,
          onDefaultProfileRequested: widget.onDefaultProfileRequested,
          revealInfoSafety: widget.revealInfoSafety,
          revealProcesverbetering: widget.revealProcesverbetering,
          revealManagementsysteem: widget.revealManagementsysteem,
          revealElearning: widget.revealElearning,
          trailing: [
            const SizedBox(width: 8),
            SlideTypeHelpToggle(
              open: _helpOpen,
              onToggle: () => setState(() => _helpOpen = !_helpOpen),
            ),
            const SizedBox(width: 6),
            SlideQualitySummaryChip(
              open: _qualityOpen,
              onToggle: () => setState(() => _qualityOpen = !_qualityOpen),
            ),
            const SizedBox(width: 6),
            _SlideSourceToggle(onTap: widget.onOpenSource),
            // Verschijnt alleen wanneer déze slide door zijn reeks klein wordt
            // gerenderd; anders neemt hij geen ruimte in.
            const SplitRunDetachChip(),
          ],
        ),
        if (_helpOpen) ...[
          const Divider(height: 1),
          SlideTypeHelpBody(type: widget.slide.type),
        ],
        if (_qualityOpen) ...[
          const Divider(height: 1),
          const SlideQualityPanel(embedded: true),
        ],
      ],
    );
  }
}

/// Schakelaar in de editor-kopregel die de gestructureerde editor inruilt voor
/// de rauwe markdown-bron van de actieve dia (#1160). Ziet eruit als de andere
/// kop-chips ([SlideTypeHelpToggle]); de markdown-editor zelf biedt de weg
/// terug naar de gestructureerde weergave.
class _SlideSourceToggle extends StatelessWidget {
  final VoidCallback onTap;

  const _SlideSourceToggle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.d('Bewerk deze dia als markdown-bron'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code, size: 14, color: AppTheme.tealFg),
              const SizedBox(width: 5),
              Text(
                l10n.d('Bron'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.tealFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarField extends StatelessWidget {
  final String label;
  final Widget child;

  const _ToolbarField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Text(
          l10n.d(label),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate400,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// De TYPE-keuze in de kopregel. Ziet eruit als een pulldown (icoon + label +
/// pijltje), maar opent dezelfde visuele kiezer als 'Slide toevoegen' — met
/// categorie-tabs, zoeken en wireframe-previews. Zo delen 'toevoegen' en
/// 'wijzigen' één bron en tonen ze exact dezelfde slidetypes.
class _SlideTypePickerButton extends StatelessWidget {
  final SlideType type;
  final VoidCallback onTap;

  const _SlideTypePickerButton({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      child: Tooltip(
        message: l10n.d('Slide type kiezen'),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            // Verticaal zo gekozen dat de knop even hoog is als de dense
            // STIJL-dropdown ernaast (beide ~24px), zodat de kopregel netjes
            // uitlijnt.
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(slideTypeIcons[type]!, size: 14, color: AppTheme.brandFg),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.d(type.label),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.brandFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.brandFg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Speakernotes veld ─────────────────────────────────────────────────────────

double _notesEditorHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.28).clamp(240.0, 420.0);

class _NotesDiscardButton extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onDiscard;
  final Color color;

  const _NotesDiscardButton({
    super.key,
    required this.controller,
    required this.onDiscard,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final enabled = value.text.trim().isNotEmpty;
        return IconButton(
          tooltip: l10n.d('Notities weggooien'),
          onPressed: enabled ? onDiscard : null,
          icon: const Icon(Icons.delete_outline, size: 16),
          color: color,
          disabledColor: color.withValues(alpha: 0.35),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        );
      },
    );
  }
}

/// Algemene achtergrondbediening, naast de instellingen van elk slidetype.
Widget _slideBackgroundGroup(
  BuildContext context,
  Slide slide,
  ValueChanged<Slide> onUpdate,
  Deck deck,
) => _SettingsGroup(
  label: context.l10n.d('Achtergrondafbeelding (optioneel)'),
  children: [
    Padding(
      padding: const EdgeInsets.all(10),
      child: SlideBackgroundEditor(
        slide: slide,
        onUpdate: onUpdate,
        projectPath: deck.projectPath,
      ),
    ),
  ],
);

// ── Timing ────────────────────────────────────────────────────────────────────

/// Automatisch doorgaan, met de duur pas ín beeld als het aan staat.
///
/// Voorheen stonden een vinkje, een label, een min, een waarde en een plus op één
/// regel, met een streepje als de instelling uit stond. Vijf bedieningselementen
/// voor één keuze, waarvan er drie meestal niets doen.
class _TimingSetting extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const _TimingSetting({required this.slide, required this.onUpdate});

  void _set(double value) {
    final clamped = (value * 10).round() / 10; // stapjes van 0,1 s
    onUpdate(slide.copyWith(advanceDuration: clamped < 0 ? 0 : clamped));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = slide.advanceDuration;
    final enabled = duration > 0;

    return _SettingRow(
      icon: Icons.timer_outlined,
      label: l10n.d('Automatisch doorgaan'),
      control: _SettingSwitch(
        value: enabled,
        semanticLabel: l10n.d('Automatisch doorgaan'),
        onChanged: (v) => _set(v ? 3.0 : 0),
      ),
      detail: enabled
          ? Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  tooltip: l10n.d('Duur verkorten'),
                  onPressed: duration > 0.1 ? () => _set(duration - 0.1) : null,
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${duration.toStringAsFixed(1)} s',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
                _StepperButton(
                  icon: Icons.add,
                  tooltip: l10n.d('Duur verlengen'),
                  onPressed: () => _set(duration + 0.1),
                ),
              ],
            )
          : null,
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: Icon(icon, size: 14),
      onPressed: onPressed,
      color: AppTheme.slate600,
    ),
  );
}

// ── Audio ─────────────────────────────────────────────────────────────────────

/// Audio bij deze slide: kiezen, en dan pas de vraag of hij vanzelf start.
///
/// De oude kaart had een eigen koptekst, een eigen kader, een eigen lettergrootte
/// en een `CheckboxListTile` — vier keer een andere maat dan de regels eromheen.
/// Nu is het één regel met de bestandsnaam en een keuzeknop; de autoplay-regel
/// verschijnt pas als er iets te spelen valt.
class _AudioSetting extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final String? projectPath;

  const _AudioSetting({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.projectPath,
  });

  Future<void> _pick() async {
    final path = await imageService.pickAudio(projectPath: projectPath);
    if (path != null) onUpdate(slide.copyWith(audioPath: path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final has = slide.audioPath.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(
          icon: Icons.audiotrack_outlined,
          label: l10n.d('Audio'),
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (has)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    // Bewust niet `Platform.pathSeparator`: die bestaat op web
                    // niet, en een pad uit een .ocideck-pakket kan van een ander
                    // besturingssysteem komen dan waarop je het opent.
                    slide.audioPath.split(RegExp(r'[\\/]')).last,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.slate700),
                  ),
                ),
              // Geen audiokiezer op web: geen projectmap om in te importeren.
              // Een bestaand pad uit een pakket blijft wél zichtbaar.
              if (supportsLocalProjectFolders)
                TextButton(
                  onPressed: _pick,
                  child: Text(
                    has ? l10n.d('Wijzigen') : l10n.d('Kiezen'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (has)
                _StepperButton(
                  icon: Icons.clear,
                  tooltip: l10n.d('Audio verwijderen'),
                  onPressed: () => onUpdate(
                    slide.copyWith(audioPath: '', audioAutoplay: false),
                  ),
                ),
            ],
          ),
        ),
        // Pas een vraag als er iets te spelen valt. Een uitgegrijsde
        // autoplay-schakelaar zonder audiobestand is ruis.
        if (has)
          _SettingRow(
            icon: Icons.play_circle_outline,
            label: l10n.d('Automatisch afspelen'),
            control: _SettingSwitch(
              value: slide.audioAutoplay,
              semanticLabel: l10n.d('Automatisch afspelen'),
              onChanged: (v) => onUpdate(slide.copyWith(audioAutoplay: v)),
            ),
          ),
      ],
    );
  }
}
