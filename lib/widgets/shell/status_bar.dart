// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

/// Label and tooltip for the status bar's filename slot, in order of
/// preference: the on-disk file name (desktop), the name we last let the
/// browser download (web has no writable path, so a saved deck would otherwise
/// keep reading as "not saved yet" next to the green "Saved" chip), or the
/// never-saved-yet placeholder. Public and pure so the web-vs-desktop
/// precedence can be unit-tested without the platform gate that drives it.
({String label, String tooltip}) deckFileStatusLabel(
  DeckState deckState,
  AppLocalizations l10n,
) {
  if (deckState.filePath != null) {
    return (
      label: p.basename(deckState.filePath!),
      tooltip: deckState.filePath!,
    );
  }
  if (deckState.downloadName != null) {
    return (
      label: deckState.downloadName!,
      tooltip: l10n.d('Opgeslagen als download in je map met downloads.'),
    );
  }
  return (label: l10n.t('notSavedYet'), tooltip: l10n.t('noFileYet'));
}

class _DeckStatusBar extends StatelessWidget {
  final Deck deck;
  final DeckState deckState;
  final String? exportDirectory;
  final Future<void> Function() onSave;
  final VoidCallback? onExport;
  final String exportTooltip;

  /// De samengevatte exportstatus plus de onderliggende kwaliteitsmeldingen
  /// (voor de tooltip-tekst van de statuschip).
  final ExportReadiness readiness;
  final SlideQualityResult quality;

  /// De externe URL waar dit deck vandaan is opgehaald (web-URL-import /
  /// `?deck=`-deeplink), of null bij een lokaal/nieuw deck. Bepaalt of de
  /// privacy-badge verschijnt.
  final String? remoteOrigin;

  const _DeckStatusBar({
    required this.deck,
    required this.deckState,
    required this.exportDirectory,
    required this.onSave,
    required this.onExport,
    required this.exportTooltip,
    required this.readiness,
    required this.quality,
    this.remoteOrigin,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skipped = deck.slides.where((s) => s.skipped).length;
    final fileStatus = deckFileStatusLabel(deckState, l10n);
    final exportLabel = exportDirectory == null
        ? l10n.t('exportNextToDeck')
        : '${l10n.t('exportFolder')}: ${p.basename(exportDirectory!)}';

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            // De linkergroep vangt al het ruimtetekort op: bij een smal
            // venster krimpen de tekstlabels (ellipsis) in plaats van dat de
            // balk overloopt; de rechtergroep blijft rechts uitgelijnd.
            Expanded(
              child: Row(
                children: [
                  _SaveStatusAction(deckState: deckState, onSave: onSave),
                  const _StatusDivider(),
                  Flexible(
                    child: _StatusItem(
                      icon: Icons.description_outlined,
                      label: fileStatus.label,
                      tooltip: fileStatus.tooltip,
                    ),
                  ),
                  if (remoteOrigin != null) ...[
                    const _StatusDivider(),
                    _RemoteOriginBadge(url: remoteOrigin!),
                  ],
                  const _GitQueueBadge(),
                  const _StatusDivider(),
                  _StatusItem(
                    icon: Icons.slideshow_outlined,
                    label: skipped == 0
                        ? '${deck.slides.length} ${l10n.t('slides')}'
                        : '${deck.slides.length} ${l10n.t('slides')} · $skipped ${l10n.t('skipped')}',
                    tooltip: skipped == 0
                        ? l10n.t('allSlidesIncluded')
                        : '$skipped ${l10n.t('skippedSlidesExcluded')}',
                    color: skipped == 0 ? null : AppTheme.goldDark,
                  ),
                  const _StatusDivider(),
                  Flexible(
                    child: _StatusItem(
                      icon: Icons.palette_outlined,
                      label: deck.themeProfile.name,
                      tooltip:
                          '${l10n.t('styleProfile')}: ${deck.themeProfile.name}',
                    ),
                  ),
                  if (deck.tlp != TlpLevel.none) ...[
                    const _StatusDivider(),
                    _StatusItem(
                      icon: Icons.shield_outlined,
                      label: deck.tlp.label,
                      tooltip: '${l10n.t('classification')}: ${deck.tlp.label}',
                      color: Color(deck.tlp.foreground),
                    ),
                  ],
                  if (deck.finalized) ...[
                    const _StatusDivider(),
                    _integrityBadge(l10n, deck),
                  ],
                ],
              ),
            ),
            _StatusItem(
              icon: Icons.folder_outlined,
              label: exportLabel,
              tooltip: exportDirectory ?? l10n.t('exportsNextToDeck'),
            ),
            const _StatusDivider(),
            _ExportReadinessChip(
              readiness: readiness,
              quality: quality,
              deckState: deckState,
              onSave: onSave,
              onExport: onExport,
            ),
            const SizedBox(width: 6),
            _StatusAction(
              icon: Icons.upload_file_outlined,
              label: l10n.t('export'),
              tooltip: exportTooltip,
              onTap: onExport,
            ),
          ],
        ),
      ),
    );
  }

  /// Documentintegriteit-badge (§8 A1): toont of het verzegelde deck intact is
  /// of ná afronden is gewijzigd. Alleen zichtbaar wanneer het deck verzegeld is.
  ///
  /// De derde stand is de eerlijke: vlak na het afronden bestaat het bestand
  /// nog niet waar het zegel over gaat, dus valt er niets na te rekenen. Groen
  /// tonen zou dan een controle voorspiegelen die niemand heeft uitgevoerd, en
  /// rood zou een manipulatie melden die er niet is.
  Widget _integrityBadge(AppLocalizations l10n, Deck deck) {
    final status = deckIntegrityStatus(deck);
    if (status == IntegrityStatus.notVerifiable) {
      return _StatusItem(
        icon: Icons.gpp_maybe_outlined,
        label: l10n.d('Zegel nog niet vastgelegd'),
        tooltip: l10n.d(
          'Er is nog geen opgeslagen bestand om het zegel tegen na te rekenen. Sla het deck op.',
        ),
        color: AppTheme.slate600,
      );
    }
    final intact = status == IntegrityStatus.intact;
    return _StatusItem(
      icon: intact ? Icons.verified_user : Icons.gpp_bad,
      label: intact
          ? l10n.d('Integriteit intact')
          : l10n.d('Gewijzigd na afronden'),
      tooltip: intact
          ? l10n.d(
              'Verzegeld met SHA-512. De inhoud komt overeen met het zegel.',
            )
          : l10n.d(
              'De inhoud wijkt af van het zegel — het bestand is na het afronden gewijzigd.',
            ),
      color: intact ? AppTheme.success700 : AppTheme.danger700,
    );
  }
}

/// Of de exportstatus een privacygegeven aanwijst — en dus het PrivacyKat-merk
/// hoort te dragen in plaats van het generieke waarschuwingsicoon. Publiek en
/// puur, zodat de keuze los van de widget te testen is.
bool statusShowsPrivacyMark(ExportReadinessStatus status) =>
    status == ExportReadinessStatus.privacyWarnings ||
    status == ExportReadinessStatus.blockedByPrivacy;

/// De exportstatus in één oogopslag: "Klaar voor export", "Nog opslaan
/// nodig", "N kwaliteitswaarschuwing(en)" of "TLP/kwaliteit blokkeert
/// export". Klikken doet het meest logische vervolg: opslaan wanneer dat de
/// blokkade is, anders de exportdialoog openen (die toont de details).
class _ExportReadinessChip extends StatelessWidget {
  final ExportReadiness readiness;
  final SlideQualityResult quality;
  final DeckState deckState;
  final Future<void> Function() onSave;
  final VoidCallback? onExport;

  const _ExportReadinessChip({
    required this.readiness,
    required this.quality,
    required this.deckState,
    required this.onSave,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const green = AppTheme.success700;
    const amber = AppTheme.amber600;
    const red = AppTheme.danger700;
    final issueCount = readiness.errorCount + readiness.warningCount;

    final (
      String label,
      IconData icon,
      Color color,
      String tooltip,
    ) = switch (readiness.status) {
      ExportReadinessStatus.ready => (
        l10n.d('Klaar voor export'),
        Icons.task_alt,
        green,
        l10n.t('exportReady'),
      ),
      // Bewust grijs en niet groen: groen is een uitspraak over wat er gevonden
      // is, en er is niet gekeken. Ook bewust niet amber — de gebruiker heeft de
      // controle zelf uitgezet, dus dit is geen alarm maar het intrekken van een
      // belofte.
      ExportReadinessStatus.readyPrivacyUnchecked => (
        l10n.d('Klaar — privacy niet gecontroleerd'),
        Icons.task_alt,
        AppTheme.slate600,
        l10n.d(
          'Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.',
        ),
      ),
      ExportReadinessStatus.qualityWarnings => (
        '$issueCount ${l10n.d('kwaliteitswaarschuwing(en)')}',
        Icons.warning_amber_outlined,
        amber,
        formatQualityExportReason(l10n, quality),
      ),
      ExportReadinessStatus.privacyWarnings => (
        '${readiness.privacyUnresolved} ${l10n.d('privacybevinding(en) zonder keuze')}',
        Icons.privacy_tip_outlined,
        amber,
        l10n.d(
          'Kies per slide wat er moet gebeuren, of exporteer bewust zoals het is.',
        ),
      ),
      ExportReadinessStatus.blockedByPrivacy => (
        l10n.d('Privacy blokkeert export'),
        Icons.privacy_tip_outlined,
        red,
        l10n.d(
          'Maak per slide een keuze (accepteren, waarschuwen of weglaten) voordat je exporteert. Dit is zo ingesteld bij Beveiliging.',
        ),
      ),
      ExportReadinessStatus.needsSave => (
        l10n.d('Nog opslaan nodig'),
        Icons.save_outlined,
        amber,
        deckState.filePath == null
            ? l10n.t('exportNeedsSave')
            : l10n.t('exportNeedsClean'),
      ),
      ExportReadinessStatus.blockedByClassification => (
        l10n.d('TLP blokkeert export'),
        Icons.shield_outlined,
        red,
        exportBlockMessage(l10n, readiness.classificationDecision) ?? '',
      ),
      ExportReadinessStatus.blockedByQuality => (
        l10n.d('Kwaliteit blokkeert export'),
        Icons.block,
        red,
        formatQualityExportReason(l10n, quality),
      ),
    };

    final onTap = readiness.status == ExportReadinessStatus.needsSave
        ? () => onSave()
        : onExport;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusShowsPrivacyMark(readiness.status)
                  ? const PrivacyKatMark(size: 12)
                  : Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
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

/// Toont hoeveel decks er nog in een git-wachtrij staan, en verdwijnt zodra
/// dat er geen zijn.
///
/// Werk dat offline is opgeslagen wácht — het is niet weg, maar het staat ook
/// nog nergens waar een ander erbij kan. Tot nu toe zag je dat alleen als je
/// er zelf naar vroeg, en dan stond het er meestal al even. Een balk die er de
/// hele tijd bij staat is precies de plek om dat stil te melden.
///
/// Bewust niet klikbaar: legen gebeurt met de bestaande opdracht in het
/// `…`-menu, die kan vragen en melden. Een badge die bij een tik een
/// netwerkactie start, doet meer dan hij belooft.
class _GitQueueBadge extends ConsumerWidget {
  const _GitQueueBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Een fout of een nog lopende telling is geen reden om iets te tonen: dan
    // wéten we het niet, en "0" beweren zou erger zijn dan zwijgen.
    final count = ref.watch(gitQueueCountProvider).asData?.value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusDivider(),
        _StatusItem(
          icon: Icons.cloud_upload_outlined,
          label: '$count ${l10n.d('wacht op verbinding')}',
          tooltip: l10n.d(
            'Opgeslagen op deze computer, nog niet in de repository. Gaat mee zodra er weer verbinding is — of nu, met "Wachtrij legen".',
          ),
          color: AppTheme.amber700,
        ),
      ],
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          // Flexible zodat het label meekrimpt (ellipsis) wanneer de
          // statusbalk het item begrenst; los daarvan blijft 210 het maximum.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: color == null
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tooltip for the remote-origin badge: the fixed privacy explanation, followed
/// by the source host (data, not translated) when it can be parsed. Pure so the
/// host-extraction + composition is unit-testable without a widget.
String remoteOriginTooltip(String url, AppLocalizations l10n) {
  final base = l10n.d(
    'Van een externe URL opgehaald; het openen heeft die server benaderd.',
  );
  final host = Uri.tryParse(url)?.host;
  return (host == null || host.isEmpty) ? base : '$base ($host)';
}

/// Non-blocking privacy badge shown when the open deck came from an external
/// URL (web URL-import / `?deck=` deeplink). Opening such a link caused the
/// device to contact that server; the badge makes that provenance visible
/// without getting in the way. Hover reveals the full explanation and host.
class _RemoteOriginBadge extends StatelessWidget {
  final String url;

  const _RemoteOriginBadge({required this.url});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PrivacyBadge(
      tooltip: remoteOriginTooltip(url, l10n),
      label: l10n.d('Extern'),
    );
  }
}

/// Waar het opslaan dat nu loopt naartoe schrijft, in leesbare vorm.
///
/// Publiek en puur zodat de bewoording los van de widget te toetsen is. Elke
/// bestemming een eigen zin, want de wachttijd verschilt met een ordegrootte en
/// de gebruiker mag weten of het aan zijn schijf of aan zijn verbinding ligt.
String saveProgressLabel(AppLocalizations l10n, SaveTarget target) {
  return switch (target) {
    SaveTarget.local => l10n.d('Opslaan…'),
    SaveTarget.webdav => l10n.d('Uploaden naar WebDAV…'),
    SaveTarget.s3 => l10n.d('Uploaden naar S3…'),
    SaveTarget.git => l10n.d('Vastleggen in git…'),
  };
}

/// De opslagchip links in de balk: normaal "Opgeslagen"/"Niet opgeslagen", en
/// tijdens een opslag een draaiende melding met de bestemming erbij.
///
/// Die tweede stand bestond niet. Een opslag naar WebDAV, S3 of git kan
/// tientallen seconden duren — één upload per mediabestand, of vier tot zeven
/// round-trips voor een commit — en het scherm veranderde in die tijd niets. Op
/// een trage verbinding is dat niet te onderscheiden van een vastgelopen app.
/// De chip is bovendien de knop zélf, dus zolang hij draait is meteen zichtbaar
/// waaróm een tweede klik niets doet.
class _SaveStatusAction extends ConsumerWidget {
  final DeckState deckState;
  final Future<void> Function() onSave;

  const _SaveStatusAction({required this.deckState, required this.onSave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final target = ref.watch(saveProgressProvider);
    if (target == null) {
      return _StatusAction(
        icon: deckState.isDirty
            ? Icons.radio_button_checked
            : Icons.check_circle_outline,
        label: deckState.isDirty ? l10n.t('unsaved') : l10n.t('saved'),
        tooltip: deckState.isDirty
            ? l10n.t('unsavedChanges')
            : l10n.t('noUnsavedChanges'),
        color: deckState.isDirty ? AppTheme.amber600 : AppTheme.success700,
        onTap: () => onSave(),
      );
    }
    final label = saveProgressLabel(l10n, target);
    return Tooltip(
      message: l10n.d(
        'Bezig met opslaan. Nog een keer opslaan doet niets tot dit klaar is.',
      ),
      // Een schermlezer krijgt de melding zonder dat de focus verspringt: dit
      // is een mededeling over wat er gebeurt, geen plek om naartoe te gaan.
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: AppTheme.amber600,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.amber600,
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

class _StatusAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled
        ? (color ?? Theme.of(context).colorScheme.secondary)
        : Theme.of(context).disabledColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Dunne verticale scheiding tussen groepen AppBar-knoppen.
class _ActionsDivider extends StatelessWidget {
  const _ActionsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
  }
}

/// TLP-classificatie als altijd zichtbare, direct instelbare chip in de
/// AppBar-titel. Toont de huidige status in de officiële TLP-kleur en opent
/// bij klikken een keuzelijst met alle niveaus (incl. "Geen").
class _TlpChip extends StatelessWidget {
  final TlpLevel tlp;
  final bool warnUnset;
  final ValueChanged<TlpLevel> onSelected;

  const _TlpChip({
    required this.tlp,
    this.warnUnset = false,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = tlp != TlpLevel.none;
    final fg = Color(tlp.foreground);
    final borderColor = warnUnset
        ? AppTheme.amber500
        : (isSet ? fg.withValues(alpha: 0.7) : Colors.white24);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isSet
            ? Colors.black
            : (warnUnset ? Colors.black45 : Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: warnUnset ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSet)
            const Icon(Icons.shield_outlined, size: 14, color: Colors.white70),
          if (!isSet) const SizedBox(width: 5),
          Text(
            isSet ? tlp.label : l10n.d('TLP'),
            style: TextStyle(
              color: isSet ? fg : Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
              letterSpacing: 0.3,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: isSet ? fg : Colors.white54,
          ),
        ],
      ),
    );

    return PopupMenuButton<TlpLevel>(
      tooltip: warnUnset
          ? l10n.d(
              'Stel een TLP-niveau in — export is geblokkeerd door het classificatiebeleid.',
            )
          : l10n.d('TLP-classificatie (Traffic Light Protocol)'),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final level in TlpLevel.values)
          PopupMenuItem<TlpLevel>(
            value: level,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: level == TlpLevel.none
                        ? Colors.transparent
                        : Color(level.foreground),
                    border: Border.all(color: AppTheme.slate400),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Text(level == TlpLevel.none ? l10n.d('Geen') : level.label),
                if (level == tlp) ...[
                  const SizedBox(width: 12),
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: AppTheme.slate600),
                ],
              ],
            ),
          ),
      ],
      child: child,
    );
  }
}
