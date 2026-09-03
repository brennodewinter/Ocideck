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
//
//  4. **Nabijheid gaat vóór volle breedte.** Een regel die de hele editorkolom
//     beslaat, zet het label op x=290 en de schakelaar op x=1330: duizend pixels
//     leegte tussen twee dingen die bij elkaar horen. Je oog moet heen en weer, en
//     bij zes regels onder elkaar raak je kwijt welke schakelaar bij welk label
//     hoort. Rechts uitlijnen is goed; het over de volle breedte doen is het niet.
//
//     De groepen zijn daarom kaarten met een eigen kolombreedte, die náást elkaar
//     staan zodra de kolom er ruimte voor heeft. Binnen zo'n kaart is de afstand
//     label→bediening een paar honderd pixels in plaats van duizend, blijft de
//     rechteruitlijning staan, en is de horizontale ruimte eindelijk ergens vóór
//     gebruikt in plaats van weggegeven. Wordt het paneel smal, dan stapelen ze
//     vanzelf terug.
part of 'editor_panel.dart';

/// De hoogte van één instellingenregel. Eén constante, zodat de regels van
/// verschillende groepen op dezelfde ritmelijn staan.
const double _kSettingRowHeight = 34;

// ── Bouwstenen ────────────────────────────────────────────────────────────────

/// Een groep instellingen als kaart.
///
/// De kaart doet twee dingen tegelijk. Ze is de *gemeenschappelijke omheining*
/// (Gestalt) die zegt dat deze regels bij elkaar horen — en ze begrenst de
/// regelbreedte, zodat het label en zijn bediening binnen één oogopslag liggen in
/// plaats van aan weerszijden van de editorkolom.
class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingsGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
          Divider(height: 1, color: AppTheme.slate200),
          const SizedBox(height: 2),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
            padding: const EdgeInsets.fromLTRB(34, 0, 10, 6),
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

  /// Wat de knop dicht toont, als dat korter mag zijn dan wat de lijst open
  /// toont. Zie de privacydispositie.
  final List<Widget> Function(BuildContext)? selectedItemBuilder;

  const _SettingDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.selectedItemBuilder,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: value,
      isDense: true,
      borderRadius: BorderRadius.circular(6),
      style: TextStyle(fontSize: 12, color: AppTheme.ink),
      items: items,
      selectedItemBuilder: selectedItemBuilder,
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
  if (slide.tableMarkOverdue) {
    badges.add(
      _SettingBadge(
        icon: Icons.event_busy_outlined,
        label: l10n.d('Datums gemarkeerd'),
      ),
    );
  }
  if (slide.type == SlideType.gantt && slide.ganttScale != 'auto') {
    badges.add(
      _SettingBadge(
        icon: Icons.calendar_today_outlined,
        label: slide.ganttScale,
      ),
    );
  }
  if (slide.ganttSections) {
    badges.add(
      _SettingBadge(icon: Icons.view_agenda_outlined, label: l10n.d('Secties')),
    );
  }
  if (slide.viewLimit?.isActive == true) {
    badges.add(
      _SettingBadge(
        icon: Icons.filter_list_outlined,
        label: l10n.d('Weergave beperken'),
      ),
    );
  }
  // Een sprong-uit verandert de volgorde tijdens presenteren (#1162): zichtbaar
  // in de ingeklapte kop, zodat je niet hoeft open te klappen om te zien dát
  // deze dia ergens anders heen springt.
  if (slide.nextAnchor.isNotEmpty) {
    badges.add(_SettingBadge(icon: Icons.alt_route, label: l10n.d('Sprong')));
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

  /// Zet de sprong-uit van deze dia (#1162): `null` = lineair, anders de
  /// deck-index van de doeldia.
  final ValueChanged<int?> onSetJump;

  const _SlideSettingsSection({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.deck,
    required this.onSetJump,
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
              onSetJump: widget.onSetJump,
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
  final ValueChanged<int?> onSetJump;

  const _SlideSettingsBody({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.deck,
    required this.onSetJump,
  });

  /// De kolombreedte waaronder een kaart niet meer fatsoenlijk uitlijnt: het
  /// langste label plus zijn bediening.
  static const double _minColumn = 330;

  @override
  Widget build(BuildContext context) {
    final groups = _groups(context);

    // Zoveel kolommen als er passen, hoogstens één per groep. Boven de ~1050px
    // (een normaal breed editorpaneel) staan de drie kaarten naast elkaar; wordt
    // het paneel smaller, dan stapelen ze vanzelf terug naar twee en naar één.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final available = constraints.maxWidth - 24;
        final fit = ((available + gap) / (_minColumn + gap)).floor();
        final columns = fit.clamp(1, groups.length);

        return Padding(
          // Onder maar 2: elke rij zet er zelf al een tussenruimte achter.
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in _rows(groups, columns)) ...[
                // `IntrinsicHeight` maakt de kaarten van één rij even hoog. Geen
                // franje: kaarten met een rafelige onderrand lezen als een fout,
                // en de blik blijft aan de langste hangen in plaats van aan de
                // inhoud.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < columns; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        // Ontbrekende kaarten in de laatste rij houden hun plek
                        // leeg, zodat de kolommen boven elkaar blijven staan.
                        Expanded(
                          child: i < row.length
                              ? row[i]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: gap),
              ],
            ],
          ),
        );
      },
    );
  }

  /// De groepen, in rijen van [columns].
  static List<List<Widget>> _rows(List<Widget> groups, int columns) => [
    for (var i = 0; i < groups.length; i += columns)
      groups.sublist(i, (i + columns).clamp(0, groups.length)),
  ];

  /// De verdiepingsschakelaar. Geldt voor elke slide, ongeacht type of
  /// stijlprofiel — vandaar dat hij buiten de voorwaardelijke rijen valt.
  Widget _depthRow(AppLocalizations l10n) => _SettingRow(
    icon: Icons.unfold_more,
    label: l10n.d('Verdieping'),
    help: l10n.d(
      'Het detail achter het verhaal. Deze slide gaat mee in de volledige export en valt weg in de beknopte — los van wie hem mag zien.',
    ),
    control: _SettingSwitch(
      value: slide.isDetail,
      semanticLabel: l10n.d('Verdieping'),
      onChanged: (v) => onUpdate(slide.copyWith(isDetail: v)),
    ),
  );

  /// Een leesbaar label voor dia [i] in de doeldia-keuzelijst: het kopje zonder
  /// opmaak, met volgnummer ervoor zodat twee dia's met dezelfde kop uit elkaar
  /// te houden zijn. Zonder kop een terugval op "Dia N".
  String _slideMenuLabel(AppLocalizations l10n, Slide s, int i) {
    final title = stripInlineMarkdown(s.title).trim();
    return '${i + 1}. ${title.isEmpty ? l10n.d('Dia') : title}';
  }

  /// De sprong-uit (#1162): naar welke dia de presentatie na deze springt. De
  /// keuzelijst toont de dia's op kop; onder water bewaart de app een stabiel
  /// anker op de doeldia. Een verweesde verwijzing (doeldia weg) valt op met een
  /// waarschuwing en de presentatie loopt gewoon lineair door.
  Widget _jumpRow(AppLocalizations l10n) {
    final selfIndex = deck.slides.indexWhere((s) => s.id == slide.id);
    final resolved = slide.nextAnchor.isEmpty
        ? -1
        : deck.slides.indexWhere((s) => s.anchor == slide.nextAnchor);
    final broken = slide.nextAnchor.isNotEmpty && resolved < 0;
    return _SettingRow(
      icon: Icons.alt_route,
      label: l10n.d('Hierna'),
      help: l10n.d(
        'Kies naar welke dia de presentatie na deze springt. Standaard is dat gewoon de volgende dia. Zo laat je een keuze-tak aan het eind terugkeren naar het menu.',
      ),
      control: _SettingDropdown<int?>(
        value: resolved < 0 ? null : resolved,
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.d('Volgende dia'))),
          for (var i = 0; i < deck.slides.length; i++)
            if (i != selfIndex)
              DropdownMenuItem(
                value: i,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _slideMenuLabel(l10n, deck.slides[i], i),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
        ],
        onChanged: onSetJump,
      ),
      detail: broken
          ? Text(
              l10n.d(
                'De doeldia bestaat niet meer — de presentatie gaat hier gewoon verder.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.warningFg),
            )
          : null,
    );
  }

  List<Widget> _groups(BuildContext context) {
    final l10n = context.l10n;
    final profile = deck.themeProfile;
    final hasLogo = profile.logoPath?.isNotEmpty == true;
    final hasFooter =
        profile.footerText.trim().isNotEmpty || profile.footerShowPageNumbers;

    return [
      // ── Op deze slide ─────────────────────────────────────────────────────
      //
      // Alleen tonen wat er te kiezen valt: zonder logo in het stijlprofiel is
      // "logo tonen" een dode schakelaar, en een dode schakelaar is erger dan
      // een ontbrekende. De groep zelf staat er altijd, want verdieping geldt
      // voor élke slide — dat is geen eigenschap van het stijlprofiel of van
      // het slidetype.
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
          _depthRow(l10n),
          if (slide.type == SlideType.table)
            _SettingRow(
              icon: Icons.event_busy_outlined,
              label: l10n.d('Verlopen datums markeren'),
              help: l10n.d(
                'Kleurt een cel met een datum van vóór vandaag rood. OciDeck kijkt naar de dag waarop u presenteert, dus een deck dat maanden later terugkomt markeert zichzelf. Alleen jjjj-mm-dd telt als datum. Staat standaard uit.',
              ),
              control: _SettingSwitch(
                value: slide.tableMarkOverdue,
                semanticLabel: l10n.d('Verlopen datums markeren'),
                onChanged: (v) => onUpdate(slide.copyWith(tableMarkOverdue: v)),
              ),
            ),
        ],
      ),

      // ── Tijdens presenteren ─────────────────────────────────────────────
      _SettingsGroup(
        label: l10n.d('Tijdens presenteren'),
        children: [
          // Alleen zinvol als er een andere dia is om heen te springen.
          if (deck.slides.length > 1) _jumpRow(l10n),
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
          if (slide.type == SlideType.gantt)
            _SettingRow(
              icon: Icons.calendar_today_outlined,
              label: l10n.d('Tijdschaal'),
              help: l10n.d(
                'De as-granulariteit van het Gantt-diagram. “Auto” kiest op basis van het datumbereik van de taken.',
              ),
              control: DropdownButton<String>(
                value: slide.ganttScale,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text(l10n.d('Auto'))),
                  DropdownMenuItem(value: 'day', child: Text(l10n.d('Dag'))),
                  DropdownMenuItem(value: 'week', child: Text(l10n.d('Week'))),
                  DropdownMenuItem(
                    value: 'month',
                    child: Text(l10n.d('Maand')),
                  ),
                ],
                onChanged: (v) =>
                    onUpdate(slide.copyWith(ganttScale: v ?? ganttScaleAuto)),
              ),
            ),
          if (slide.type == SlideType.gantt)
            _SettingRow(
              icon: Icons.view_agenda_outlined,
              label: l10n.d('Sectiedelingen'),
              help: l10n.d(
                'Behandel een taaknaam die met “## ” begint als een sectiekop in het diagram.',
              ),
              control: _SettingSwitch(
                value: slide.ganttSections,
                semanticLabel: l10n.d('Sectiedelingen'),
                onChanged: (v) => onUpdate(slide.copyWith(ganttSections: v)),
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
                      level == TlpLevel.none ? l10n.d('Geen') : level.menuLabel,
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
              'Volg de presentatie: deze slide doet wat de presentatie als geheel doet. Alleen melden: de bevinding wordt geteld, maar de ontvanger ziet niets — de gegevens staan er gewoon. Accepteren: de gegevens horen hier en de melding verdwijnt. Accepteren + waarschuwen: de ontvanger ziet een badge dat er persoonsgegevens op de slide staan. Weglaten: de gevonden gegevens worden onleesbaar gemaakt op het scherm en in de export — je markdown-bestand houdt de oorspronkelijke tekst.',
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
              // Open toont de lijst de volle zin ("Weglaten uit tonen en
              // exporteren"), want daar kies je op. Dicht toont ze het korte
              // woord, want daar lees je alleen de stand af — en die volle zin
              // zou een kaartbreedte opeisen die de rest van de kolom niet
              // heeft.
              selectedItemBuilder: (context) => [
                Text(privacyDispositionLabel(l10n, null)),
                for (final d in PrivacyDisposition.values)
                  Text(privacyDispositionShortLabel(l10n, d)),
              ],
              onChanged: (v) =>
                  onUpdate(slide.copyWith(privacy: v, clearPrivacy: v == null)),
            ),
          ),
        ],
      ),
      if (_supportsViewLimit(slide.type))
        _ViewLimitSetting(slide: slide, onUpdate: onUpdate),
    ];
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
