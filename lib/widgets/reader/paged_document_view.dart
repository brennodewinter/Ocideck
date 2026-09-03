import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/page_size.dart';
import '../../models/settings.dart'
    show
        ThemeProfile,
        documentBodyFontSizeToCssPx,
        kDocumentDefaultBodyFontSize;
import '../../services/document_footnote_setup.dart';
import '../../services/document_pagination.dart';
import '../../utils/footnotes.dart';
import '../../theme/app_theme.dart';
import '../document_page_chrome.dart';
import 'document_markdown_view.dart';

/// Millimeters naar beeldpunten. 96 dpi is de CSS-referentie (1 inch = 96 px),
/// dus dit is dezelfde maat als waarin de HTML-export haar pagina uitmeet — een
/// A4 wordt hier net zo breed als daar.
const double kPxPerMm = 96 / 25.4;
const double _documentChromeMinHeightPx = 56;

/// De tekstbreedte van één pagina in beeldpunten: de paginabreedte min de
/// zijmarges. Puur, en hier thuis omdat dit dezelfde paginameetkunde is als
/// waarmee de vellen worden opgezet — de schrijfstand rekent er zijn
/// tekstkolom mee uit, zodat een pagina-einde daar op dezelfde breedte valt
/// als op papier.
double pageTextWidthPx(PageSizeSpec size, PageMargins margins) {
  final (widthMm, _) = size.dimensions;
  return ((widthMm - margins.leftMm - margins.rightMm) * kPxPerMm).clamp(
    kPxPerMm,
    double.infinity,
  );
}

/// Toont een document als échte pagina's: op maat, met de gekozen marges, een
/// kop- en voetband per pagina en een paginanummer.
///
/// Waarom niet gewoon een lange rol met een streepje erin: een pagina-einde
/// bepaalt wat er nog nét op de bladzijde komt, en dat is precies wat je bij
/// het schrijven wilt zien. De einden worden daarom niet geschat maar gemeten —
/// het document wordt één keer doorlopend gerenderd, de blokhoogtes worden
/// opgenomen, en [documentPageOffsets] bepaalt daarmee waar de vellen breken.
///
/// De drukkersafloop ([PageMargins.bleedMm]) wordt getoond als een rand rondom
/// het snijformaat, met een snijlijn erlangs: zo zie je wat de drukker wegsnijdt
/// zonder dat je het hoeft voor te stellen.
class PagedDocumentView extends StatefulWidget {
  const PagedDocumentView({
    super.key,
    required this.markdown,
    required this.pageSize,
    required this.margins,
    this.profile,
    this.projectPath,
    this.scale = 1.0,
    this.chapterPageBreak = false,
    this.footnotePlacement = FootnotePlacement.page,
    this.tlp = TlpLevel.none,
    this.fields = const {},
  });

  final String markdown;
  final PageSizeSpec pageSize;
  final PageMargins margins;
  final ThemeProfile? profile;
  final String? projectPath;

  /// Zoomfactor op het vel. 1,0 is ware grootte op een 96-dpi scherm.
  final double scale;

  /// Laat elk hoofdstuk (`H1`) op een nieuw vel beginnen — de instelling
  /// "Nieuw hoofdstuk op een nieuwe pagina", die de export ook honoreert.
  final bool chapterPageBreak;

  /// Waar de voetnoten komen: onderaan het blad waar de verwijzing staat, of
  /// achterin het document. Komt uit de front matter van het document zelf
  /// (`reference-location:`); zie [documentFootnotePlacement].
  final FootnotePlacement footnotePlacement;

  /// De ene classificatie van het hele document, zichtbaar op elk vel.
  final TlpLevel tlp;
  final Map<String, String> fields;

  @override
  State<PagedDocumentView> createState() => _PagedDocumentViewState();
}

class _PagedDocumentViewState extends State<PagedDocumentView> {
  /// De gemeten hoogte per blok, of `null` zolang er nog niet gemeten is. Tot
  /// dat moment staat er een meetopstelling buiten beeld in plaats van een
  /// weergave.
  List<double>? _blockHeights;

  /// De hoogtes die tijdens de meetronde binnenkomen, op blokvolgorde. De
  /// voetnoten meten mee, achter de blokken aan.
  final Map<int, double> _measuring = {};

  /// De gemeten hoogte van elke voetnoot, in dezelfde volgorde als [_notes].
  List<double>? _noteHeights;

  /// De voetnoten van dit document, genummerd in leesvolgorde — één keer
  /// ontleed per tekst, niet per opbouw. Het ontleden loopt het hele document
  /// door, en dat drie keer per frame doen is werk dat niets oplevert.
  late List<Footnote> _notes = documentFootnotes(widget.markdown);

  /// De zoektekst van elk blok, in dezelfde volgorde als de blokken. Om dezelfde
  /// reden bewaard: hij komt uit een volledige ontleding.
  late List<String> _blockTexts = DocumentMarkdownView.blockTexts(
    widget.markdown,
  );

  /// Tijdlijnkaarten en hun eerste-kolommarkering, met exact dezelfde
  /// blokindexen als [_blockTexts] en de gemeten hoogtes.
  late var _timelinePagination = documentTimelinePaginationData(
    widget.markdown,
  );

  /// Of het document afbeeldingsblokken bevat. Alleen dan blijft de meetboom
  /// gemonteerd na de eerste ronde — een afbeelding decodeert asynchroon, dus
  /// zijn hoogte komt pas later binnen. Een document zonder afbeeldingen heeft
  /// alleen synchrone blokken (tekst, tabellen, code), en voor die volstaat een
  /// eenmalige meting: de boom hoeft niet te blijven staan.
  ///
  /// Niet `late final`: na het invoegen van de eerste afbeelding of een
  /// gewijzigd projectPath (waardoor een relatief beeld al of niet resolveert)
  /// moet opnieuw bepaald worden of de meetboom moet blijven staan (#1652).
  late bool _hasImages = _containsImageBlock(widget.markdown);

  /// Of de noten onderaan het blad komen te staan. Achterin is geen aparte
  /// tekenroute: dan lopen ze gewoon als laatste blokken in de tekststroom mee
  /// en worden ze net als al het andere over de vellen verdeeld.
  bool get _notesOnPage =>
      widget.footnotePlacement == FootnotePlacement.page && _notes.isNotEmpty;

  /// De ruimte die elk blok bovenop zijn eigen hoogte op het vel opeist: de
  /// noten die er voor het eerst vanuit worden aangehaald.
  ///
  /// Bij het blok en niet bij de pagina, omdat de noot met zijn verwijzing
  /// meereist: schuift het blok naar het volgende vel, dan schuift de noot mee
  /// en komt de ruimte hier vanzelf weer vrij. Zie [documentPageOffsets].
  List<double> _reservedRoom(int blockCount) {
    final heights = _noteHeights;
    if (!_notesOnPage || heights == null) return const [];
    final notes = _notes;
    final indexOfLabel = {
      for (var i = 0; i < notes.length; i++) notes[i].label: i,
    };
    final texts = _blockTexts;
    final room = List<double>.filled(blockCount, 0);
    final placed = <String>{};
    for (var block = 0; block < texts.length && block < blockCount; block++) {
      for (final label in footnoteReferencesIn(texts[block])) {
        final note = indexOfLabel[label];
        if (note == null || !placed.add(label)) continue;
        room[block] += heights[note] + _noteGapPx;
      }
    }
    return room;
  }

  /// Lucht tussen twee noten, en tussen de tekst en de scheidingslijn. Ruim
  /// genomen: de scheiding hoort ook ergens, en een noot die net niet past is
  /// erger dan een vel met een centimeter wit onderaan.
  static const double _noteGapPx = 10;

  /// Welke noten er onderaan welk vel horen te staan.
  ///
  /// Een noot hoort bij het vel waarop zijn éérste verwijzing valt. Twee keer
  /// dezelfde noot op twee bladzijden zou de lezer laten denken dat het er twee
  /// zijn, en het nummer spreekt dat tegen.
  List<List<Footnote>> _notesPerPage(
    List<double> offsets,
    List<double> heights,
  ) {
    final pages = [for (var i = 0; i < offsets.length; i++) <Footnote>[]];
    if (!_notesOnPage) return pages;
    final notes = _notes;
    final byLabel = {for (final note in notes) note.label: note};
    final texts = _blockTexts;
    final placed = <String>{};
    var top = 0.0;
    for (var block = 0; block < heights.length; block++) {
      if (block < texts.length) {
        for (final label in footnoteReferencesIn(texts[block])) {
          final note = byLabel[label];
          if (note == null || !placed.add(label)) continue;
          pages[_pageOf(top, offsets)].add(note);
        }
      }
      top += heights[block];
    }
    for (final page in pages) {
      page.sort((a, b) => a.number.compareTo(b.number));
    }
    return pages;
  }

  /// Het vel waarop hoogte [y] van het doorlopende document valt.
  static int _pageOf(double y, List<double> offsets) {
    var page = 0;
    for (var i = 1; i < offsets.length; i++) {
      // Een halve punt speling: de posities komen uit een optelling van gemeten
      // hoogtes en die eindigt zelden precies op de grens.
      if (offsets[i] <= y + 0.5) page = i;
    }
    return page;
  }

  @override
  void didUpdateWidget(PagedDocumentView old) {
    super.didUpdateWidget(old);
    // Andere tekst, vel, of projectpad betekent opnieuw meten; de oude einden
    // slaan dan nergens meer op. Het projectpad meeswegen: een relatief beeld
    // resolveert al of niet afhankelijk van de basis, en dan verandert de
    // afbeeldingshoogte (#1652).
    if (widget.markdown != old.markdown ||
        widget.pageSize != old.pageSize ||
        widget.margins != old.margins ||
        widget.profile != old.profile ||
        widget.chapterPageBreak != old.chapterPageBreak ||
        widget.footnotePlacement != old.footnotePlacement ||
        widget.projectPath != old.projectPath) {
      _blockHeights = null;
      _measuring.clear();
      _notes = documentFootnotes(widget.markdown);
      _blockTexts = DocumentMarkdownView.blockTexts(widget.markdown);
      _timelinePagination = documentTimelinePaginationData(widget.markdown);
      _hasImages = _containsImageBlock(widget.markdown);
    }
  }

  /// De papierkleur van het vel: die van het stijlprofiel wanneer er een is —
  /// dezelfde die `DocumentMarkdownView` op het tekstvlak zet — en anders de
  /// themakleur, zodat het vel in donkere modus meedimt.
  Color get _paperColor {
    final background = widget.profile?.slideBackgroundColor;
    if (background == null || background.isEmpty) return AppTheme.paper;
    return AppTheme.parseHexColor(background, fallback: AppTheme.paper);
  }

  (double width, double height) get _sheetPx {
    final (w, h) = widget.pageSize.dimensions;
    final bleed = widget.margins.bleedMm * 2;
    return ((w + bleed) * kPxPerMm, (h + bleed) * kPxPerMm);
  }

  double get _contentWidthPx {
    final (w, _) = widget.pageSize.dimensions;
    // Verdediging in de diepte: de parse-lagen hierboven zouden ongeldige
    // marges allang moeten afvangen, maar een negatieve tekstspiegel die
    // hier toch doorheen glipt crasht de layout. Knel af op 1 mm — te smal
    // om te lezen, maar eindig en positief, dus de boom overleeft.
    return ((w - widget.margins.leftMm - widget.margins.rightMm) * kPxPerMm)
        .clamp(kPxPerMm, double.infinity);
  }

  double get _contentHeightPx {
    final (_, h) = widget.pageSize.dimensions;
    final pageHeight = h * kPxPerMm;
    return (pageHeight - _contentTopPx - _contentBottomPx).clamp(
      kPxPerMm,
      double.infinity,
    );
  }

  bool get _hasPageChrome =>
      widget.profile != null || widget.tlp != TlpLevel.none;

  double get _chromeTopInsetPx =>
      _contentInsetPx(widget.margins.topMm, header: true);

  double get _timelineContinuationRoomPx =>
      _hasPageChrome && _timelinePagination.blocks.isNotEmpty ? 28 : 0;

  double get _contentTopPx => _chromeTopInsetPx + _timelineContinuationRoomPx;

  double get _contentBottomPx =>
      _contentInsetPx(widget.margins.bottomMm, header: false);

  double _contentInsetPx(double marginMm, {required bool header}) {
    final margin = marginMm * kPxPerMm;
    final minimum = _chromeMinimumPx(header);
    return _hasPageChrome && margin < minimum ? minimum : margin;
  }

  double _chromeMinimumPx(bool header) {
    final profile = widget.profile;
    if (profile == null) return _documentChromeMinHeightPx;
    final path = profile.effectiveDocumentLogoPath?.trim() ?? '';
    final logoInBand =
        path.isNotEmpty &&
        profile.documentLogoPosition.startsWith(header ? 'top' : 'bottom');
    if (!logoInBand) return _documentChromeMinHeightPx;
    final logoWidth = (profile.effectiveDocumentLogoSize * 0.45).clamp(
      36.0,
      144.0,
    );
    final logoHeight = (logoWidth * 0.5).clamp(22.0, 72.0) + 13;
    return logoHeight > _documentChromeMinHeightPx
        ? logoHeight
        : _documentChromeMinHeightPx;
  }

  @override
  Widget build(BuildContext context) {
    final heights = _blockHeights;
    // Bevat het document afbeeldingen, dan blijft de meetboom buiten beeld
    // staan — een afbeelding decodeert asynchroon, dus haar hoogte komt pas na
    // de eerste ronde binnen. Stond de boom dan al af, dan bleef de paginering
    // op de placeholder-hoogte staan en rotte stil: de einden wezen naar een
    // regel tekst waar inmiddels een afbeelding van een paar centimeter staat.
    // Nu hermeet de boom zodra een blokhoogte verandert (zie [_onMeasured]), en
    // de vellen erboven volgen. Zonder afbeeldingen zijn alle blokken synchroon
    // en volstaat een eenmalige meting: de boom hoeft niet te blijven staan.
    if (!_hasImages) {
      if (heights == null) return _measure();
      return _pages(heights);
    }
    return Stack(
      fit: StackFit.expand,
      children: [_measure(), if (heights != null) _pages(heights)],
    );
  }

  /// De vellen, opgebouwd uit de gemeten hoogtes. Bestaat als aparte methode
  /// omdat [build] de meetboom er altijd onder laat staan.
  Widget _pages(List<double> heights) {
    final document = DocumentMarkdownView(
      widget.markdown,
      maxTextWidth: null,
      themeProfile: widget.profile,
      chartTheme: widget.profile,
      // Een `---` is hier het pagina-einde zelf; hem ook tekenen zou elk vers
      // vel met een streep laten openen.
      hideRules: true,
      // Onderaan het blad tekent dít scherm ze, per vel; achterin lopen ze
      // gewoon als laatste blokken in de stroom mee.
      footnotesAtEnd: !_notesOnPage,
      // Een breed diagram schaalt af op de vaste kolombreedte, net als in de
      // PDF — een schuifbalk snijdt hier af op een vel.
      scaleMermaidToFit: true,
    );
    final offsets = documentPageOffsets(
      blockHeights: heights,
      pageHeight: _contentHeightPx,
      // Een `---` en (naar keuze) elk hoofdstuk beginnen een nieuw vel, net als
      // in de export. Zonder dit zei het scherm iets anders dan de druk.
      forcedBreakBefore: documentForcedPageBreaks(
        widget.markdown,
        chapterBreak: widget.chapterPageBreak,
      ),
      // Een kop blijft niet alleen (of met één losse regel) onderaan een vel
      // achter, maar schuift mee naar de tekst waar hij bij hoort.
      keepWithNext: documentHeadingBlocks(widget.markdown),
      minKeepHeight: documentKeepWithNextHeight(
        MediaQuery.textScalerOf(context),
        bodyFontSize: documentBodyFontSizeToCssPx(
          widget.profile?.documentBodyFontSize ?? kDocumentDefaultBodyFontSize,
        ),
      ),
      // De noten van een blok staan onderaan hetzelfde vel als dat blok, dus
      // eisen ze daar ruimte op.
      reservedRoom: _reservedRoom(heights.length),
    );
    final notesPerPage = _notesPerPage(offsets, heights);
    final timelineContinuationPages = documentContinuationPageBlocks(
      blockHeights: heights,
      pageOffsets: offsets,
      continuationBlocks: _timelinePagination.continuationBlocks,
      continuableBlocks: _timelinePagination.blocks,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Een vel dat breder is dan het venster zou onbereikbaar zijn: de
        // vellen staan in een verticale rol, dus er is geen horizontale
        // schuifbalk om naar de rechterhelft te gaan. A0 staat gewoon in de
        // maatlijst, dus dat geval is niet theoretisch — schaal terug tot het
        // past, nooit verder omhoog dan ware grootte.
        final (sheetW, _) = _sheetPx;
        final room = constraints.maxWidth - 32;
        final fit = room > 0 && sheetW > room ? room / sheetW : 1.0;
        return SingleChildScrollView(
          // Ingezoomd wordt het vel breder dan het venster. Zonder deze tweede,
          // horizontale rol zou de rechterhelft niet alleen onbereikbaar zijn
          // maar ook een overloopfout geven — de vellen staan in een verticale
          // kolom, en die knijpt niets af.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              // Minstens zo breed als het venster, zodat een vel dat er wél in
              // past gewoon gecentreerd blijft staan.
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Center(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    for (var i = 0; i < offsets.length; i++) ...[
                      _sheet(
                        context,
                        document,
                        offsets[i],
                        // Waar dít vel ophoudt: bij het begin van het volgende, niet
                        // een volle paginahoogte verder. Een blok dat niet meer paste
                        // is doorgeschoven, en dan hoort de onderkant van dit vel wit
                        // te blijven in plaats van de eerste regels van dat blok
                        // doormidden te tonen.
                        i + 1 < offsets.length
                            ? offsets[i + 1] - offsets[i]
                            : _contentHeightPx,
                        i + 1,
                        offsets.length,
                        fit,
                        notesPerPage[i],
                        switch (timelineContinuationPages[i]) {
                          final block? =>
                            _timelinePagination.markerLabels[block] ?? '',
                          null => null,
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Rendert het document één keer buiten beeld op de tekstbreedte van de
  /// pagina, met een meter om elk blok. Buiten het venster in plaats van in een
  /// `Offstage`: die meet zijn kind niet gegarandeerd uit, en zonder meting
  /// komt er nooit een pagina.
  Widget _measure() {
    final blockCount = _blockTexts.length;
    // De noten meten in dezelfde ronde mee, elk apart: alleen zo weet de
    // paginaverdeling hoeveel ruimte er onder een blad weg moet. Ze krijgen
    // indexen áchter de blokken, zodat één teller volstaat.
    final notes = _notesOnPage ? _notes : const <Footnote>[];
    // Eindnoten (achterin het document) meten als één extra blok: de
    // DocumentMarkdownView tekent ze buiten de blockWrapper, dus de gewone
    // blokmeting ziet ze niet. Zonder deze extra meting vallen lange eindnoten
    // voorbij de laatste berekende pagina en worden ze afgeknipt (#1653).
    final endnotes = !_notesOnPage && _notes.isNotEmpty
        ? _notes
        : const <Footnote>[];
    final total = blockCount + notes.length + (endnotes.isNotEmpty ? 1 : 0);
    return ClipRect(
      child: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            left: -1e5,
            top: 0,
            width: _contentWidthPx,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DocumentMarkdownView(
                    widget.markdown,
                    maxTextWidth: null,
                    themeProfile: widget.profile,
                    chartTheme: widget.profile,
                    hideRules: true,
                    footnotesAtEnd: !_notesOnPage,
                    scaleMermaidToFit: true,
                    blockWrapper: (index, block) => _MeasuredBlock(
                      index: index,
                      onMeasured: (i, height) =>
                          _onMeasured(i, height, blockCount, total),
                      child: block,
                    ),
                  ),
                  for (var n = 0; n < notes.length; n++)
                    _MeasuredBlock(
                      index: blockCount + n,
                      onMeasured: (i, height) =>
                          _onMeasured(i, height, blockCount, total),
                      // Eén noot per meting: de scheidingslijn en de tussenruimte
                      // horen bij het vel, niet bij de noot, en die zitten in
                      // [_noteGapPx].
                      child: DocumentFootnotesView(
                        notes: [notes[n]],
                        themeProfile: widget.profile,
                      ),
                    ),
                  if (endnotes.isNotEmpty)
                    _MeasuredBlock(
                      index: blockCount + notes.length,
                      onMeasured: (i, height) =>
                          _onMeasured(i, height, blockCount, total),
                      child: DocumentFootnotesView(
                        notes: endnotes,
                        themeProfile: widget.profile,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMeasured(int index, double height, int blockCount, int total) {
    if (!mounted) return;
    // Geen slot: een afbeelding die na de eerste ronde decodeert, verandert de
    // hoogte van zijn blok, en dan hoort de paginering dat te zien. Alleen een
    // waarde die echt anders is loopt door — een gelijke hoogte stopt hier, dus
    // een stabiele boom bouwt niet eindeloos om.
    if (_measuring[index] == height) return;
    _measuring[index] = height;
    if (_measuring.length < total) return;
    // Pagina-noten staan op indexen blockCount..blockCount+pageFootnoteCount-1.
    // Eindnoten (één blok) staan daarna op index blockCount+pageFootnoteCount.
    final pageFootnoteCount = _notesOnPage ? _notes.length : 0;
    final hasEndnotesBlock = !_notesOnPage && _notes.isNotEmpty;
    final heights = [
      for (var i = 0; i < blockCount; i++) _measuring[i] ?? 0,
      if (hasEndnotesBlock) _measuring[blockCount + pageFootnoteCount] ?? 0,
    ];
    final noteHeights = [
      for (var i = blockCount; i < blockCount + pageFootnoteCount; i++)
        _measuring[i] ?? 0,
    ];
    final prev = _blockHeights;
    final prevNotes = _noteHeights;
    if (prev != null &&
        _listEq(prev, heights) &&
        prevNotes != null &&
        _listEq(prevNotes, noteHeights)) {
      return;
    }
    setState(() {
      _blockHeights = heights;
      _noteHeights = noteHeights;
    });
  }

  static bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  /// De kop- of voetband van één vel, in de marge geplaatst.
  Widget _chromeBand(
    ThemeProfile profile,
    double bleedPx,
    int pageNumber, {
    required bool header,
  }) => Positioned(
    // Binnen de zijmarges, niet tegen de snijrand: een kop- of voetband hoort
    // op dezelfde lijn te beginnen en eindigen als de tekst eronder. Tegen de
    // papierrand geplakt liep het woordmerk er half af.
    left: (widget.margins.leftMm * kPxPerMm) + bleedPx,
    right: (widget.margins.rightMm * kPxPerMm) + bleedPx,
    top: header ? bleedPx : null,
    bottom: header ? null : bleedPx,
    height: _chromeBandHeight(
      header ? widget.margins.topMm : widget.margins.bottomMm,
      header: header,
    ),
    child: Align(
      alignment: header ? Alignment.bottomCenter : Alignment.topCenter,
      child: DocumentChromeBand(
        profile: profile,
        header: header,
        tlp: widget.tlp,
        fields: widget.fields,
        pageLabel: '$pageNumber',
        projectPath: widget.projectPath,
        compact: true,
      ),
    ),
  );

  double _chromeBandHeight(double marginMm, {required bool header}) {
    final marginHeight = marginMm * kPxPerMm;
    final minimum = _chromeMinimumPx(header);
    return marginHeight < minimum ? minimum : marginHeight;
  }

  /// Eén vel: papier, afloopmarkering, kop- en voetband en het venster op het
  /// doorlopende document dat op deze pagina hoort.
  Widget _sheet(
    BuildContext context,
    Widget document,
    double offset,
    double windowHeight,
    int pageNumber,
    int pageCount,
    double fit,
    List<Footnote> notes,
    String? timelineContinuationMarker,
  ) {
    final (sheetW, sheetH) = _sheetPx;
    final bleedPx = widget.margins.bleedMm * kPxPerMm;
    final theme = Theme.of(context);
    final profile = widget.profile;
    final chrome = profile ?? const ThemeProfile();
    final page = Container(
      width: sheetW,
      height: sheetH,
      decoration: BoxDecoration(
        // Hetzelfde papier als waar de tekst op staat. Niet hardgecodeerd wit
        // (dan staat er in donkere modus een verblindend blok), maar ook niet
        // blind de themakleur: is er een stijlprofiel, dan schildert de
        // weergave het tekstvlak met de achtergrond daaruit, en een vel met een
        // andere kleur rand dan midden is geen vel meer.
        color: _paperColor,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // De kop- en voetband staan ín de marge, niet in het tekstvlak.
          // Zo hoort het op papier — en het is bovendien de enige plek waar ze
          // kúnnen staan: hingen ze boven en onder de tekst in dezelfde kolom,
          // dan aten ze hoogte op waar de paginaverdeling al over had beschikt,
          // en verdween er onderaan elk vel een stuk tekst dat nergens meer
          // terugkwam.
          if (profile != null || widget.tlp != TlpLevel.none) ...[
            _chromeBand(chrome, bleedPx, pageNumber, header: true),
            _chromeBand(chrome, bleedPx, pageNumber, header: false),
          ],
          Positioned(
            left: (widget.margins.leftMm * kPxPerMm) + bleedPx,
            top: _contentTopPx + bleedPx,
            width: _contentWidthPx,
            // Precies het stuk document dat op dit vel hoort: niet een volle
            // paginahoogte, maar tot waar het volgende vel begint.
            height: windowHeight,
            child: ClipRect(
              // Met een sleutel: dit is hét venster op het document, en een
              // toets moet het kunnen aanwijzen zonder per ongeluk een van de
              // andere clips in de boom te pakken.
              key: const Key('document-page-window'),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                // ponytail: ceiling — elk vel bouwt het volledige document
                // op in de widgetboom (N × volledige layout). RepaintBoundary
                // laat de compositor het gerasteriseerde vel cachen, zodat
                // tenminste de paint-kost na de eerste frame meevalt. Een
                // volledige oplossing (elk blok één keer renderen, per vel
                // gesegmenteerd) vereist een andere paginaverdelingsarchitectuur.
                child: RepaintBoundary(
                  child: Transform.translate(
                    offset: Offset(0, -offset),
                    child: SizedBox(width: _contentWidthPx, child: document),
                  ),
                ),
              ),
            ),
          ),
          if (timelineContinuationMarker != null)
            _timelineContinuationLabel(
              theme,
              bleedPx,
              timelineContinuationMarker,
            ),
          // De noten staan onderaan het tekstvlak, tegen de ondermarge: dat is
          // wat een voetnoot ís. De ruimte ervoor is bij de opmaak al van dit
          // vel afgehaald (zie [_reservedRoom]), dus ze botsen nooit met de
          // tekst erboven.
          if (notes.isNotEmpty)
            Positioned(
              left: (widget.margins.leftMm * kPxPerMm) + bleedPx,
              right: (widget.margins.rightMm * kPxPerMm) + bleedPx,
              bottom: _contentBottomPx + bleedPx,
              // ponytail: ceiling — een enkele noot die langer is dan de
              // paginahoogte kan niet over vellen worden verdeeld; we clippen
              // hem binnen het tekstvlak zodat hij niet overlapt met de
              // hoofdtekst. Een volledige oplossing vereist het splitsen van
              // de noot over pagina's, wat een grotere herontwerp van de
              // paginaverdeling vraagt.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _contentHeightPx),
                child: ClipRect(
                  child: DocumentFootnotesView(
                    notes: notes,
                    themeProfile: widget.profile,
                  ),
                ),
              ),
            ),
          if (widget.margins.hasBleed)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(bleedPx),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final label = context.l10n
        .d('Pagina {n} van {m}')
        .replaceAll('{n}', '$pageNumber')
        .replaceAll('{m}', '$pageCount');
    return Semantics(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `scale` is de keuze van de aanroeper, `fit` de correctie die een
          // vel dat breder is dan het venster binnen beeld houdt.
          SizedBox(
            // Met een sleutel: dit is het vel zoals het in beeld staat, de maat
            // waar een toets over gaat.
            key: const Key('document-sheet'),
            width: sheetW * widget.scale * fit,
            height: sheetH * widget.scale * fit,
            child: FittedBox(fit: BoxFit.contain, child: page),
          ),
          const SizedBox(height: 4),
          // Het nummer staat ónder het vel, niet erop: op het papier zou het
          // doen alsof het meegedrukt wordt, en dat is het niet — een
          // paginanummer in de uitvoer komt uit de voetband van het
          // stijlprofiel. Zonder dit bijschrift had een document zonder
          // profielband nergens een nummer, terwijl je deze stand juist
          // opent om te zien wat op welke bladzijde komt.
          ExcludeSemantics(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Staat in de bovenmarge en verandert daardoor de gemeten documentstroom
  /// niet; de eerste kaart op het vel tekent de rail zelf opnieuw.
  Widget _timelineContinuationLabel(
    ThemeData theme,
    double bleedPx,
    String marker,
  ) => Positioned(
    key: const Key('document-timeline-continuation'),
    left: (widget.margins.leftMm * kPxPerMm) + bleedPx,
    right: (widget.margins.rightMm * kPxPerMm) + bleedPx,
    top: _chromeTopInsetPx + bleedPx + 4,
    child: Text(
      marker.isEmpty
          ? context.l10n.d('Tijdlijn · vervolg')
          : '${context.l10n.d('Tijdlijn · vervolg')} — $marker',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

/// Meet de hoogte van één documentblok en meldt hem terug.
///
/// Per blok, niet in één keer over de hele kolom: tijdens een layout mag een
/// render-object alleen zijn *eigen* maat lezen, niet die van een kleinkind.
/// Elk blok meet dus zichzelf.
class _MeasuredBlock extends SingleChildRenderObjectWidget {
  const _MeasuredBlock({
    required this.index,
    required this.onMeasured,
    required super.child,
  });

  final int index;
  final void Function(int index, double height) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredBlock(index, onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredBlock renderObject,
  ) => renderObject
    ..index = index
    ..onMeasured = onMeasured;
}

class _RenderMeasuredBlock extends RenderProxyBox {
  _RenderMeasuredBlock(this.index, this.onMeasured);

  int index;
  void Function(int index, double height) onMeasured;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size.height;
    // Ná de frame melden: een setState tijdens de layout mag niet.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => onMeasured(index, measured),
    );
  }
}

/// Of de markdown een regel bevat die precies één afbeelding is — dezelfde
/// herkenning als `document_markdown_blocks._parseImageLine`. Alleen dan heeft
/// de paginaweergave de meetboom nodig om te blijven staan: een afbeelding
/// decodeert asynchroon, en pas als haar hoogte binnenkomt klopt het pagina-einde.
bool _containsImageBlock(String markdown) {
  for (final line in markdown.split('\n')) {
    if (_imageLinePattern.hasMatch(line.trim())) return true;
  }
  return false;
}

///zelfde patroon als `document_markdown_blocks._imageLinePattern` — zie daar
/// voor de ondersteuning van angle-bracket en ontsnapte haakjes.
final RegExp _imageLinePattern = RegExp(r'^!\[([^\]]*)\]\((.+)\)$');
