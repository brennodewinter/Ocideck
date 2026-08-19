// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De voorvertoningen van de stijlbouwer: één per vlak. Ze staan los van de
// bouwer zelf omdat ze samen over het regelplafond van dat bestand heen groeien
// — een extension op dezelfde privéklasse, dus dezelfde velden en dezelfde
// aanroepen.
//
// Elk vlak toont wat je er kunt zetten en niets meer. Dat is de reden dat het
// algemene vlak een blad zonder kop- en voetband tekent: die band hoort bij het
// documentvlak, en een voorvertoning die iets laat zien dat je hier niet kunt
// bijstellen stuurt je naar de verkeerde plek.
part of '../settings_dialog.dart';

extension _StylePreviews on _DocumentStyleBuilder {
  /// Eén stuk markdown, getekend met de kleuren en het lettertype van het
  /// profiel dat nu bewerkt wordt. Gedeeld door het algemene en het
  /// documentvlak, zodat dezelfde tekst er in beide even zo uitziet.
  Widget _previewMarkdown(
    String markdown,
    Color paper,
    Color ink,
    Color accent,
  ) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: paper.computeLuminance() < 0.45
              ? Brightness.dark
              : Brightness.light,
          surface: paper,
        ).copyWith(
          primary: accent,
          onSurface: ink,
          onSurfaceVariant: ink.withValues(alpha: 0.72),
          outlineVariant: ink.withValues(alpha: 0.25),
          surfaceContainerHighest: accent.withValues(alpha: 0.12),
        );
    return Theme(
      data: ThemeData(
        colorScheme: scheme,
        fontFamily: _themeProfile.fontFamily,
        textTheme: ThemeData.light().textTheme.apply(
          fontFamily: _themeProfile.fontFamily,
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      child: DocumentMarkdownView(
        markdown,
        maxTextWidth: null,
        themeProfile: _themeProfile,
        chartTheme: _themeProfile,
      ),
    );
  }

  /// De voorvertoning van het algemene vlak: een blad met alles erop wat beide
  /// vlakken delen — koppen, tekst, een opsomming, een checklist, een tabel en
  /// een broncodeblok.
  ///
  /// Bewust zonder de kop- en voetband: die hoort bij het documentvlak. Een
  /// voorvertoning die iets toont dat je hier niet kunt zetten laat je zoeken
  /// naar een knop die op dit vlak niet bestaat.
  Widget _generalStylePreview(AppLocalizations l10n) {
    final paper = AppTheme.parseHexColor(_themeProfile.slideBackgroundColor);
    final ink = AppTheme.parseHexColor(_themeProfile.textColor);
    final accent = AppTheme.parseHexColor(_themeProfile.accentColor);
    return _previewFrame(
      l10n,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1 / 1.414,
          child: Container(
            key: const Key('general-style-preview'),
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 20),
            decoration: BoxDecoration(
              color: paper,
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.shadow20,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: ink,
                fontFamily: _themeProfile.fontFamily,
              ),
              child: SingleChildScrollView(
                primary: false,
                child: _previewMarkdown(
                  _generalPreviewMarkdown(l10n),
                  paper,
                  ink,
                  accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// De voorbeeldtekst van het algemene vlak. Elk blok staat er omdat er een
  /// instelling bij hoort die hier te zetten is; een blok zonder knop eronder
  /// zou alleen ruimte kosten.
  String _generalPreviewMarkdown(AppLocalizations l10n) {
    final sample = l10n.d('Voorbeeldtekst');
    final content = l10n.d('Inhoud');
    return '''
# ${l10n.d('Voorvertoning')}

${l10n.d('De snelle bruine vos springt over de luie hond.')}

## ${l10n.d('Besluit gevraagd')}

- $sample
- $content

- [x] $sample
- [ ] $content

| ${l10n.d('Tabel')} | $content |
| --- | --- |
| $sample | $content |

```
$sample
```
''';
  }

  Widget _documentStylePreview(AppLocalizations l10n) {
    final paper = AppTheme.parseHexColor(_themeProfile.slideBackgroundColor);
    final ink = AppTheme.parseHexColor(_themeProfile.textColor);
    final accent = AppTheme.parseHexColor(_themeProfile.accentColor);
    return _previewFrame(
      l10n,
      trailing: SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(l10n.d('Titel'))),
          ButtonSegment(value: true, label: Text(l10n.d('Inhoud'))),
        ],
        selected: {_stylePreviewShowsContent},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (value) =>
            _rebuild(() => _stylePreviewShowsContent = value.first),
      ),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1 / 1.414,
          child: Container(
            key: const Key('document-style-preview'),
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(34, 28, 34, 24),
            decoration: BoxDecoration(
              color: paper,
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.shadow20,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: ink,
                fontFamily: _themeProfile.fontFamily,
              ),
              child: _stylePreviewShowsContent
                  ? _documentPreviewContent(l10n, paper, ink, accent)
                  : _documentPreviewTitle(l10n, ink, accent),
            ),
          ),
        ),
      ),
    );
  }

  Widget _presentationStylePreview(AppLocalizations l10n) {
    final profile = owner._editedProfile();
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: l10n.d('Voorvertoning'),
      bullets: [
        l10n.d('De snelle bruine vos springt over de luie hond.'),
        l10n.d('Besluit gevraagd'),
        l10n.d('Voorbeeldtekst'),
      ],
    );
    return _previewFrame(
      l10n,
      child: Container(
        key: const Key('presentation-style-preview'),
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppTheme.shadow20,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SlidePreviewWidget(
          slide: slide,
          themeProfile: profile,
          slideNumber: 2,
          slideCount: 8,
        ),
      ),
    );
  }

  Widget _documentPreviewTitle(AppLocalizations l10n, Color ink, Color accent) {
    final profile = owner._editedProfile();
    return Column(
      children: [
        DocumentChromeBand(profile: profile, header: true, compact: true),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                l10n.d('Documentstijl'),
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _themeProfile.name,
                style: TextStyle(
                  color: ink,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.d('De snelle bruine vos springt over de luie hond.'),
                style: TextStyle(
                  color: ink.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
        DocumentChromeBand(
          profile: profile,
          header: false,
          pageLabel: '1 / 8',
          compact: true,
        ),
      ],
    );
  }

  Widget _documentPreviewContent(
    AppLocalizations l10n,
    Color paper,
    Color ink,
    Color accent,
  ) {
    final markdown =
        '''
# ${l10n.d('Voorvertoning')}

${l10n.d('De snelle bruine vos springt over de luie hond.')}

## ${l10n.d('Besluit gevraagd')}

- ${l10n.d('Voorbeeldtekst')}
- ${l10n.d('Inhoud')}
''';
    final profile = owner._editedProfile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocumentChromeBand(profile: profile, header: true, compact: true),
        const SizedBox(height: 22),
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            child: _previewMarkdown(markdown, paper, ink, accent),
          ),
        ),
        DocumentChromeBand(
          profile: profile,
          header: false,
          pageLabel: '3 / 8',
          compact: true,
        ),
      ],
    );
  }
}

/// De grijze kaart om elke voorvertoning: dezelfde rand, dezelfde kop en
/// dezelfde ruimte, welk vlak er ook in staat. Wisselen van vlak verspringt
/// dan niets behalve de inhoud zelf.
Widget _previewFrame(
  AppLocalizations l10n, {
  required Widget child,
  Widget? trailing,
}) {
  final title = Text(
    l10n.d('Voorvertoning'),
    style: TextStyle(color: AppTheme.slate700, fontWeight: FontWeight.w700),
  );
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.slate200,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.slate300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trailing == null)
          title
        else
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [title, trailing],
          ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}
