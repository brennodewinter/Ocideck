// Part of the editor_panel library — see editor_panel.dart.
//
// De slide-instellingen: alles wat je per slide kunt zetten en wat niet in de
// type-specifieke editor thuishoort. Logo, footer, timing, tabelbewerking,
// audio, TLP en de privacydispositie.
//
// ── Waarom dit blok is herzien ───────────────────────────────────────────────
//
// Deze sectie is per feature aangegroeid, en dat was eraan te zien. Zeven
// instellingen in één platte lijst, met drie verschillende rijvormen door elkaar:
// een audiokaart over de volle breedte, vinkjes mét het label eráchter (bediening
// links), en dropdowns mét het label ervóór (bediening rechts). Er lijnde niets
// uit, de scheidingslijnen stonden op willekeurige plekken, en de timingregel
// propte een vinkje, een label, een min, een waarde en een plus op één regel.
//
// Drie dingen zijn veranderd:
//
//  1. **Groepen.** De instellingen zijn niet één lijst maar drie vragen: wat
//     staat er óp deze slide, wat gebeurt er tijdens het presenteren, en wat mag
//     de ontvanger ermee. Dat is ook de volgorde waarin je eraan denkt.
//
//  2. **Eén rijvorm.** Icoon · label · (uitleg) ········ bediening. De bediening
//     staat altijd rechts, of het nu een schakelaar of een keuzelijst is. Dat is
//     dezelfde vorm als het instellingenvenster van de app zelf gebruikt.
//
//  3. **De ingeklapte kop vertelt wat er afwijkt.** Voorheen zag je alleen een
//     TLP-badge. Dat was niet alleen lelijk maar ook een gat: de dispositie
//     "weglaten" bepáált wat de ontvanger krijgt, en die kon je niet zien zonder
//     open te klappen. Nu staat elke afwijking van de standaard als badge in de
//     kop.
part of 'editor_panel.dart';

/// De hoogte van één instellingenregel. Eén constante, zodat de regels van
/// verschillende groepen op dezelfde ritmelijn staan.
const double _kSettingRowHeight = 34;

// ── Bouwstenen ────────────────────────────────────────────────────────────────

/// Een groep instellingen onder een rustige kop.
class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingsGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppTheme.slate400,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// Eén instellingenregel: icoon · label · (uitleg) ········ bediening.
///
/// Alle regels in dit blok gaan hier doorheen. Dat is het hele punt: zolang elke
/// regel zijn eigen `Row` optuigde, lijnde er niets uit en dreef de vorm bij elke
/// nieuwe instelling verder uiteen.
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// De bediening, rechts. Een schakelaar, een keuzelijst, een stepper.
  final Widget control;

  /// Uitleg achter een ⓘ naast het label. Kort houden: dit is een tooltip, geen
  /// handleiding.
  final String? help;

  /// Een tweede regel onder deze, ingesprongen — voor bediening die pas zin
  /// heeft als de schakelaar aan staat (zie de timing).
  final Widget? detail;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.control,
    this.help,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kSettingRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.slate500),
                const SizedBox(width: 10),
                // Eén `Expanded` om label + uitleg heen, en niets anders dat
                // flexibel is. Een `Flexible` naast een `Spacer` lijkt hetzelfde
                // te doen, maar die twee délen de vrije ruimte — en dan landt de
                // bediening bij elke regel op een andere x, precies het gebrek aan
                // uitlijning dat dit herontwerp moest oplossen.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ),
                      if (help != null) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: help!,
                          child: Icon(
                            Icons.info_outline,
                            size: 13,
                            color: AppTheme.slate400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                control,
              ],
            ),
          ),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 12, 6),
            child: detail,
          ),
      ],
    );
  }
}

/// De schakelaar rechts. Compact, en dezelfde die het instellingenvenster
/// gebruikt — een instelling hoort er overal in de app hetzelfde uit te zien.
class _SettingSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  const _SettingSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    toggled: value,
    // Standaard is een Switch fors; dit blok staat dicht opeen. `Transform`
    // omdat Switch zelf geen dichtheid kent — schalen is hier het enige middel
    // dat de raakvlakken niet kapotmaakt.
    child: Transform.scale(
      scale: 0.8,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// De keuzelijst rechts, zonder streep eronder.
class _SettingDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _SettingDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: value,
      isDense: true,
      borderRadius: BorderRadius.circular(6),
      style: TextStyle(fontSize: 12, color: AppTheme.ink),
      items: items,
      onChanged: onChanged,
    ),
  );
}

// ── De ingeklapte kop ─────────────────────────────────────────────────────────

/// Eén afwijking van de standaard, als badge in de ingeklapte kop.
class _SettingBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Een badge die verandert wát de ontvanger krijgt, draagt kleur; de rest is
  /// grijs. Anders schreeuwt "logo uit" even hard als "gegevens weggelaten".
  ///
  /// De amber is dezelfde als die van het privacy-shield op de slide zelf
  /// (`overlays.dart`). Eén betekenis, één kleur — een tweede accentkleur voor
  /// hetzelfde begrip is precies hoe een interface langzaam onleesbaar wordt.
  final bool prominent;

  const _SettingBadge({
    required this.icon,
    required this.label,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = prominent ? AppTheme.warningFg : AppTheme.slate600;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: prominent ? AppTheme.warningBg : AppTheme.slate200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wat er op deze slide afwijkt van de standaard.
///
/// Dit is de reden dat de kop bestaat. Een ingeklapt blok dat niets prijsgeeft,
/// dwingt je het bij elke slide open te klappen om te zien of er iets bijzonders
/// aan de hand is — en dus doe je dat niet, en mis je het.
List<Widget> slideSettingBadges(AppLocalizations l10n, Slide slide) {
  final badges = <Widget>[];

  // De TLP-badge blijft bewust neutraal. TLP heeft zijn eigen kleurtaal (AMBER,
  // RED) en die op eigen houtje overschrijven met een accentkleur zou een niveau
  // suggereren dat er niet staat. Het label zégt al wat het is.
  if (slide.tlp != TlpLevel.none) {
    badges.add(
      _SettingBadge(icon: Icons.shield_outlined, label: slide.tlp.label),
    );
  }
  if (slide.privacy != null) {
    badges.add(
      _SettingBadge(
        icon: Icons.privacy_tip_outlined,
        label: privacyDispositionShortLabel(l10n, slide.privacy!),
        // Alleen 'weglaten' verandert wat de ontvanger krijgt; de rest is een
        // aantekening van de auteur.
        prominent: slide.privacy == PrivacyDisposition.redact,
      ),
    );
  }
  if (slide.advanceDuration > 0) {
    badges.add(
      _SettingBadge(
        icon: Icons.timer_outlined,
        label: '${slide.advanceDuration.toStringAsFixed(1)} s',
      ),
    );
  }
  if (slide.audioPath.isNotEmpty) {
    badges.add(_SettingBadge(icon: Icons.audiotrack, label: l10n.d('Audio')));
  }
  if (slide.tableEditable) {
    badges.add(
      _SettingBadge(icon: Icons.edit_outlined, label: l10n.d('Bewerkbaar')),
    );
  }
  return badges;
}

/// Het korte label van een dispositie, voor de badge.
String privacyDispositionShortLabel(
  AppLocalizations l10n,
  PrivacyDisposition d,
) => switch (d) {
  PrivacyDisposition.warn => l10n.d('Melden'),
  PrivacyDisposition.accept => l10n.d('Geaccepteerd'),
  PrivacyDisposition.shield => l10n.d('Gewaarschuwd'),
  PrivacyDisposition.redact => l10n.d('Weggelaten'),
};

/// Het volledige label van een dispositie, voor de keuzelijst.
String privacyDispositionLabel(AppLocalizations l10n, PrivacyDisposition? d) =>
    switch (d) {
      null => l10n.d('Volg de presentatie'),
      PrivacyDisposition.warn => l10n.d('Alleen melden'),
      PrivacyDisposition.accept => l10n.d('Accepteren'),
      PrivacyDisposition.shield => l10n.d('Accepteren + waarschuwen'),
      PrivacyDisposition.redact => l10n.d('Weglaten uit tonen en exporteren'),
    };

// ── De sectie ─────────────────────────────────────────────────────────────────

/// De slide-instellingen als inklapbaar blok, onder de type-specifieke editor en
/// boven de notities. Standaard ingeklapt, zodat de editorkolom rustig blijft.
class _SlideSettingsSection extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final Deck deck;

  const _SlideSettingsSection({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.deck,
  });

  @override
  State<_SlideSettingsSection> createState() => _SlideSettingsSectionState();
}

class _SlideSettingsSectionState extends State<_SlideSettingsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final badges = slideSettingBadges(l10n, widget.slide);

    return Material(
      color: AppTheme.slate50,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppTheme.slate200),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (open) => setState(() => _expanded = open),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(Icons.tune, size: 18, color: AppTheme.slate500),
          title: Row(
            children: [
              Text(
                l10n.d('Slide-instellingen'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate600,
                ),
              ),
              const SizedBox(width: 8),
              // De badges vatten samen wat je níét ziet. Staat het blok open, dan
              // zie je het wél — en dan zijn ze dubbelop: "3,0 s" in de kop én de
              // stepper eronder. Dus alleen ingeklapt.
              //
              // De badges mogen wegvallen als de kolom smal wordt; de kop zelf
              // niet. Vandaar Expanded om de badges heen, niet om de titel.
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  runSpacing: 2,
                  children: _expanded ? const [] : badges,
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            _SlideSettingsBody(
              slide: widget.slide,
              onUpdate: widget.onUpdate,
              imageService: widget.imageService,
              deck: widget.deck,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// De drie groepen.
///
/// De volgorde is de volgorde waarin je eraan denkt: eerst wat er op de slide
/// staat, dan wat er gebeurt terwijl je 'm toont, en als laatste wat de ontvanger
/// ermee mag — want dat is de vraag die je pas stelt als de slide af is.
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
    final l10n = context.l10n;
    final profile = deck.themeProfile;
    final hasLogo = profile.logoPath?.isNotEmpty == true;
    final hasFooter =
        profile.footerText.trim().isNotEmpty || profile.footerShowPageNumbers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Op deze slide ───────────────────────────────────────────────────
        //
        // Alleen tonen wat er te kiezen valt: zonder logo in het stijlprofiel is
        // "logo tonen" een dode schakelaar, en een dode schakelaar is erger dan
        // een ontbrekende.
        if (hasLogo || hasFooter)
          _SettingsGroup(
            label: l10n.d('Op deze slide'),
            children: [
              if (hasLogo)
                _SettingRow(
                  icon: Icons.branding_watermark_outlined,
                  label: l10n.d('Logo tonen'),
                  control: _SettingSwitch(
                    value: slide.showLogo,
                    semanticLabel: l10n.d('Logo tonen'),
                    onChanged: (v) => onUpdate(slide.copyWith(showLogo: v)),
                  ),
                ),
              if (hasFooter)
                _SettingRow(
                  icon: Icons.short_text_outlined,
                  label: l10n.d('Footer tonen'),
                  control: _SettingSwitch(
                    value: slide.showFooter,
                    semanticLabel: l10n.d('Footer tonen'),
                    onChanged: (v) => onUpdate(slide.copyWith(showFooter: v)),
                  ),
                ),
            ],
          ),

        // ── Tijdens presenteren ─────────────────────────────────────────────
        _SettingsGroup(
          label: l10n.d('Tijdens presenteren'),
          children: [
            _TimingSetting(slide: slide, onUpdate: onUpdate),
            if (slide.type == SlideType.table)
              _SettingRow(
                icon: Icons.edit_outlined,
                label: l10n.d('Tabel bewerkbaar'),
                help: l10n.d(
                  'Laat je de tabel tijdens het presenteren voor de zaal aanpassen. Staat standaard uit.',
                ),
                control: _SettingSwitch(
                  value: slide.tableEditable,
                  semanticLabel: l10n.d('Tabel bewerkbaar'),
                  onChanged: (v) => onUpdate(slide.copyWith(tableEditable: v)),
                ),
              ),
            if (slide.type != SlideType.video)
              _AudioSetting(
                slide: slide,
                onUpdate: onUpdate,
                imageService: imageService,
                projectPath: deck.projectPath,
              ),
          ],
        ),

        // ── Wat de ontvanger ermee mag ──────────────────────────────────────
        _SettingsGroup(
          label: l10n.d('Classificatie en privacy'),
          children: [
            _SettingRow(
              icon: Icons.shield_outlined,
              label: l10n.d('TLP van deze slide'),
              help: slideTlpHelpText(l10n),
              control: _SettingDropdown<TlpLevel>(
                value: slide.tlp,
                items: [
                  for (final level in TlpLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: Text(
                        level == TlpLevel.none
                            ? l10n.d('Geen')
                            : level.menuLabel,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onUpdate(slide.copyWith(tlp: v));
                },
              ),
            ),
            _SettingRow(
              icon: Icons.privacy_tip_outlined,
              label: l10n.d('Persoonsgegevens'),
              help: l10n.d(
                'Accepteren: de gegevens horen hier en de melding verdwijnt. Accepteren + waarschuwen: de ontvanger ziet een badge dat er persoonsgegevens op de slide staan. Weglaten: de gevonden gegevens worden onleesbaar gemaakt op het scherm en in de export — je markdown-bestand houdt de oorspronkelijke tekst.',
              ),
              control: _SettingDropdown<PrivacyDisposition?>(
                value: slide.privacy,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(privacyDispositionLabel(l10n, null)),
                  ),
                  for (final d in PrivacyDisposition.values)
                    DropdownMenuItem(
                      value: d,
                      child: Text(privacyDispositionLabel(l10n, d)),
                    ),
                ],
                onChanged: (v) => onUpdate(
                  slide.copyWith(privacy: v, clearPrivacy: v == null),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

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
