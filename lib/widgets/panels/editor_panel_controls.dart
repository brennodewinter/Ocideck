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
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SlideType>(
                  value: slide.type,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(6),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final type in SlideType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              slideTypeIcons[type]!,
                              size: 14,
                              color: AppTheme.navy,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                l10n.d(type.label),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onTypeChanged(v);
                  },
                ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.teal,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final profile in profileItems)
                      DropdownMenuItem(
                        value: profile.name,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.palette_outlined,
                              size: 14,
                              color: AppTheme.teal,
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
            Tooltip(
              message:
                  '${context.l10n.d('Terug naar standaardstijl')} ${defaultProfile.name}',
              child: IconButton(
                onPressed: onDefaultProfileRequested,
                icon: const Icon(Icons.restart_alt, size: 16),
                color: AppTheme.teal,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ],
          ...trailing,
        ],
      ),
    );
  }
}

/// De editor-kopregel: TYPE- en STIJL-keuze plus de compacte schakelaars voor
/// hulp, slidekwaliteit en slide-instellingen op één regel. Elke schakelaar
/// klapt z'n inhoud eronder uit (elk beheert z'n eigen open/dicht-toestand).
class _EditorHeaderBar extends StatefulWidget {
  final Slide slide;
  final List<ThemeProfile> profiles;
  final ThemeProfile activeProfile;
  final ThemeProfile defaultProfile;
  final ValueChanged<SlideType> onTypeChanged;
  final ValueChanged<ThemeProfile> onProfileChanged;
  final VoidCallback onDefaultProfileRequested;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final Deck deck;

  const _EditorHeaderBar({
    required this.slide,
    required this.profiles,
    required this.activeProfile,
    required this.defaultProfile,
    required this.onTypeChanged,
    required this.onProfileChanged,
    required this.onDefaultProfileRequested,
    required this.onUpdate,
    required this.imageService,
    required this.deck,
  });

  @override
  State<_EditorHeaderBar> createState() => _EditorHeaderBarState();
}

class _EditorHeaderBarState extends State<_EditorHeaderBar> {
  bool _helpOpen = false;
  bool _qualityOpen = false;
  bool _settingsOpen = false;

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
            _SlideSettingsToggle(
              slide: widget.slide,
              open: _settingsOpen,
              onToggle: () => setState(() => _settingsOpen = !_settingsOpen),
            ),
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
        if (_settingsOpen) ...[
          const Divider(height: 1),
          _SlideSettingsBody(
            slide: widget.slide,
            onUpdate: widget.onUpdate,
            imageService: widget.imageService,
            deck: widget.deck,
          ),
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

// ── Timing instelling ─────────────────────────────────────────────────────────

class _SlideTimingControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideTimingControl({required this.slide, required this.onUpdate});

  void _setDuration(double value) {
    final clamped = (value * 10).round() / 10; // snap to 0.1s
    onUpdate(slide.copyWith(advanceDuration: clamped < 0 ? 0 : clamped));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = slide.advanceDuration > 0;
    final duration = slide.advanceDuration;

    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 14, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Checkbox(
            value: enabled,
            onChanged: (v) => _setDuration(v == true ? 3.0 : 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Automatisch doorgaan na'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
          const SizedBox(width: 8),
          // Minus knop
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: l10n.d('Duur verkorten'),
              icon: const Icon(Icons.remove, size: 14),
              onPressed: enabled && duration > 0.1
                  ? () => _setDuration(duration - 0.1)
                  : null,
              color: AppTheme.slate500,
            ),
          ),
          // Waarde
          Container(
            width: 52,
            alignment: Alignment.center,
            child: Text(
              enabled ? '${duration.toStringAsFixed(1)} s' : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? AppTheme.slate600 : AppTheme.slate400,
              ),
            ),
          ),
          // Plus knop
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: l10n.d('Duur verlengen'),
              icon: const Icon(Icons.add, size: 14),
              onPressed: enabled ? () => _setDuration(duration + 0.1) : null,
              color: AppTheme.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide logo-zichtbaarheid ──────────────────────────────────────────────

class _SlideLogoControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideLogoControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(
            Icons.branding_watermark_outlined,
            size: 14,
            color: AppTheme.slate500,
          ),
          const SizedBox(width: 8),
          Checkbox(
            value: slide.showLogo,
            onChanged: (v) => onUpdate(slide.copyWith(showLogo: v ?? true)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Logo tonen op deze slide'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide footer-zichtbaarheid ────────────────────────────────────────────

class _SlideFooterControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideFooterControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.short_text_outlined, size: 14, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Checkbox(
            value: slide.showFooter,
            onChanged: (v) => onUpdate(slide.copyWith(showFooter: v ?? true)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Footer tonen op deze slide'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ],
      ),
    );
  }
}

// ── Per-tabel: bewerkbaar tijdens presenteren ─────────────────────────────────

class _SlideTableEditControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideTableEditControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, size: 14, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Checkbox(
            value: slide.tableEditable,
            onChanged: (v) =>
                onUpdate(slide.copyWith(tableEditable: v ?? false)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l10n.d('Tabel bewerkbaar tijdens presenteren'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide TLP-classificatie ───────────────────────────────────────────────

class _SlideTlpControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideTlpControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppTheme.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 14, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('TLP van deze slide'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
          ),
          Tooltip(
            message: slideTlpHelpText(l10n),
            child: Icon(Icons.info_outline, size: 14, color: AppTheme.slate400),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<TlpLevel>(
              value: slide.tlp,
              isDense: true,
              borderRadius: BorderRadius.circular(6),
              style: TextStyle(fontSize: 12, color: AppTheme.ink),
              items: [
                for (final level in TlpLevel.values)
                  DropdownMenuItem(
                    value: level,
                    child: Text(
                      level == TlpLevel.none ? l10n.d('Geen') : level.menuLabel,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onUpdate(slide.copyWith(tlp: v));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gebundelde slide-instellingen ─────────────────────────────────────────────

/// Compacte "Slide-instellingen"-schakelaar voor de editor-kopregel; de
/// bijbehorende controls verschijnen via [_SlideSettingsBody]. Een gezette
/// TLP-markering blijft als badge zichtbaar zonder open te klappen (belangrijk
/// voor de classificatie), de rest zie je bij het aanklikken.
class _SlideSettingsToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final Slide slide;

  const _SlideSettingsToggle({
    required this.open,
    required this.onToggle,
    required this.slide,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Icon-only zodat de vijf items op één regel passen; het label staat in de
    // tooltip. Een gezette TLP-markering blijft wél als badge zichtbaar.
    return Tooltip(
      message: l10n.d('Slide-instellingen'),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 15, color: AppTheme.slate500),
              if (slide.tlp != TlpLevel.none) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.slate200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    slide.tlp.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
              ],
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 15,
                color: AppTheme.slate500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// De controls achter de [_SlideSettingsToggle]: audio, logo, footer,
/// tabel-optie, timing en TLP van deze slide.
class _SlideSettingsBody extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final Deck deck;

  const _SlideSettingsBody({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.deck,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slide.type != SlideType.video) ...[
          Container(
            color: AppTheme.slate50,
            padding: const EdgeInsets.all(12),
            child: AudioAttachmentEditor(
              slide: slide,
              imageService: imageService,
              onUpdate: onUpdate,
              projectPath: deck.projectPath,
            ),
          ),
          const Divider(height: 1),
        ],
        if (deck.themeProfile.logoPath?.isNotEmpty == true) ...[
          _SlideLogoControl(slide: slide, onUpdate: onUpdate),
          const Divider(height: 1),
        ],
        if (deck.themeProfile.footerText.trim().isNotEmpty ||
            deck.themeProfile.footerShowPageNumbers) ...[
          _SlideFooterControl(slide: slide, onUpdate: onUpdate),
          const Divider(height: 1),
        ],
        if (slide.type == SlideType.table) ...[
          _SlideTableEditControl(slide: slide, onUpdate: onUpdate),
          const Divider(height: 1),
        ],
        _SlideTimingControl(slide: slide, onUpdate: onUpdate),
        const Divider(height: 1),
        _SlideTlpControl(slide: slide, onUpdate: onUpdate),
      ],
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
        return Tooltip(
          message: l10n.d('Notities weggooien'),
          child: IconButton(
            onPressed: enabled ? onDiscard : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            color: color,
            disabledColor: color.withValues(alpha: 0.35),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        );
      },
    );
  }
}
