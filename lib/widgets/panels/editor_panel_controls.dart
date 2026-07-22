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
    this.trailing = const [],
  });

  /// Open dezelfde visuele kiezer als 'Slide toevoegen' om het slide-type te
  /// wijzigen. Is de huidige slide al een informatieveiligheid-type, dan tonen
  /// we die categorie óók als de module uit staat — anders zit je vast en kun
  /// je zo'n slide niet naar een ander security-type ombouwen.
  Future<void> _pickType(BuildContext context) async {
    final reveal =
        revealInfoSafety ||
        slide.type.category == SlideCategory.informationSecurity;
    final picked = await AddSlideDialog.show(context, revealInfoSafety: reveal);
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

    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
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
          ...trailing,
        ],
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
  final bool revealInfoSafety;

  const _EditorHeaderBar({
    required this.slide,
    required this.profiles,
    required this.activeProfile,
    required this.defaultProfile,
    required this.onTypeChanged,
    required this.onProfileChanged,
    required this.onDefaultProfileRequested,
    required this.revealInfoSafety,
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
