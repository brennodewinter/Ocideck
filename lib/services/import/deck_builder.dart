import 'package:crypto/crypto.dart' as crypto;

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../markdown_safety.dart';
import '../web_asset_store.dart';
import 'models/body_block.dart';
import 'models/conversion_issue.dart';
import 'models/slide_failure_policy.dart';
import 'models/source_chart.dart';
import 'models/source_deck.dart';
import 'models/source_image.dart';
import 'models/source_slide.dart';
import 'models/source_video.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'pipeline/unconverted_tracker.dart';
import 'utils/import_text_sanitizer.dart';
import 'utils/safe_extensions.dart';

/// Hoeveel items een geïmporteerde dia standaard tóónt voordat de
/// weergavelimiet ingrijpt. Ruim genoeg voor een gewone dia, krap genoeg om een
/// duizendregelige brontabel niet onleesbaar te laten worden (#672).
const kImportedBulletLimit = 8;
const kImportedTableRowLimit = 12;

/// The outcome of building an OciDeck [Deck] from a classified source deck: the
/// deck itself plus the [ProblemSlide]s that carried real (non-salvaged) loss,
/// which the UI surfaces for a per-slide decision.
class BuiltDeck {
  const BuiltDeck({
    required this.deck,
    required this.problemSlides,
    this.safetyFindings = const [],
  });

  final Deck deck;
  final List<ProblemSlide> problemSlides;

  /// De uitkomst van de fail-closed backstop: uitvoerbare inhoud die na het
  /// bouwen tóch in het gegenereerde `.md` bleef staan (#876). Leeg = veilig.
  /// Niet-leeg betekent dat de import geweigerd hoort te worden — de importbouw
  /// neutraliseert brontekst, maar de definitieve serialisatie wordt hier nog
  /// eens door dezelfde poort gehaald die ook een vreemd bestand bij het openen
  /// tegenhoudt, zodat een geïmporteerd deck niet alsnog geweigerd wordt bij het
  /// heropenen.
  final List<MarkdownSafetyFinding> safetyFindings;
}

/// Turns a format-neutral [SourceDeck] plus its per-slide [ClassifiedSlide]s
/// into a real OciDeck [Deck] built on the actual `Slide`/`Deck` model.
///
/// This is Keiko's writer replaced on OciDeck's own object model: instead of
/// emitting Marp Markdown, it constructs `Slide` objects via
/// [Slide.create] + [Slide.copyWith] and lets the existing
/// `MarkdownService`/`FileService` serialise them. Nothing here writes Markdown
/// text for a structured slide — only free-Markdown note/salvage bodies, which
/// are genuinely free text.
///
/// ## Image materialisation
///
/// Each [SourceImage] carries raw [SourceImage.bytes]. Rather than Keiko's
/// shared `images/<sha256>` scheme, the builder hands the bytes to
/// [WebAssetStore.put], which returns a `mem:` path, and stores that path in the
/// slide's `imagePath`. When [FileService.saveDeck] later runs,
/// `ImageService.copyImagesToProject` materialises every `mem:` path into the
/// deck's own `images/` folder with content-based de-dup
/// (`resolveAssetDestinationForBytes`) — the exact route a remote (`mem:`) deck
/// already takes on save. So the bytes travel with the deck, land per-deck, and
/// de-dup on save without this layer touching the filesystem (web-safe).
///
/// Identical images are de-duped up front too: the same bytes (by SHA-256) reuse
/// one `mem:` path, so a logo repeated on ten slides becomes one store entry and
/// materialises once — de-dup by content, but through the idiomatic filename,
/// not a `<sha256>.<ext>` name.
class DeckBuilder {
  /// Bouwt een deck; [translate] vertaalt de notitietekst die in het document
  /// van de gebruiker belandt.
  ///
  /// De naad zit op de bouwer en niet in elke methodesignatuur: de service
  /// maakt één [DeckBuilder] met `l10n.d` erin, en alles wat een notitiedia
  /// schrijft gebruikt dezelfde functie. Zonder een UI (een test, een
  /// opdrachtregel) is het [identityTranslator] en blijft de tekst Nederlands.
  /// De keuze om híer te vertalen en niet bij het tonen is bewust: de
  /// notitiedia is inhoud die in het `.md` wordt opgeslagen (#806) — zie
  /// [UnconvertedTracker].
  DeckBuilder({this.translate = identityTranslator});

  /// Vertaalt één Nederlandse bronstring; zie [ImportTextTranslator].
  final ImportTextTranslator translate;

  /// `mem:` path per image content hash, so identical images share one entry.
  final Map<String, String> _memPathBySha = {};

  /// Build an OciDeck [Deck] from [sourceDeck] and its [classified] slides
  /// (aligned by order). [title] becomes the deck title.
  BuiltDeck build(
    SourceDeck sourceDeck,
    List<ClassifiedSlide> classified, {
    required String title,
    Map<int, SlideFailurePolicy> policies = const {},
  }) {
    final slides = <Slide>[];
    final problemSlides = <ProblemSlide>[];

    for (final c in classified) {
      final issues = _conversionIssuesFor(c);
      final realLoss = issues.where((i) => !i.isSalvaged).toList();

      // Het beleid geldt alleen voor een dia met écht verlies. Een dia die
      // schoon converteert laat je met rust, ook als de gebruiker "overslaan"
      // als algemene voorkeur koos — anders gooit één keuze zijn hele deck weg.
      final policy = realLoss.isEmpty
          ? SlideFailurePolicy.bestEffort
          : (policies[c.source.index] ?? SlideFailurePolicy.bestEffort);
      final effective =
          policy == SlideFailurePolicy.imageOnly && c.source.images.isEmpty
          // Een afbeeldingsdia zonder afbeelding is niets; dan is overslaan
          // eerlijker dan een lege dia.
          ? SlideFailurePolicy.skip
          : policy;

      switch (effective) {
        case SlideFailurePolicy.bestEffort:
          slides.add(_buildSlide(c));
        case SlideFailurePolicy.imageOnly:
          slides.add(_imageOnlySlide(c.source));
        case SlideFailurePolicy.skip:
          break;
      }

      if (issues.isNotEmpty) {
        slides.add(
          _noteSlide(
            c.source.index + 1,
            issues,
            heading: _headingFor(effective, c.source.index + 1),
          ),
        );
      }
      if (realLoss.isNotEmpty) {
        problemSlides.add(_problemSlide(c.source, realLoss));
      }
    }

    if (sourceDeck.issues.isNotEmpty) {
      slides.add(_deckNoteSlide(sourceDeck.issues));
    }

    final deck = Deck(title: title, author: sourceDeck.author, slides: slides);
    return BuiltDeck(deck: deck, problemSlides: problemSlides);
  }

  /// De probleemdia's van [classified], zónder een deck te bouwen.
  ///
  /// Het beslismoment valt tússen classificeren en bouwen: de gebruiker moet
  /// kunnen kiezen wát er met een dia gebeurt vóórdat die dia er is. Dit is
  /// dezelfde verliesberekening als [build] doet, maar zonder dia's te
  /// construeren of afbeeldingen te materialiseren — vragen mag niet duurder
  /// zijn dan doen.
  List<ProblemSlide> analyse(List<ClassifiedSlide> classified) => [
    for (final c in classified)
      if (_conversionIssuesFor(c).where((i) => !i.isSalvaged).toList()
          case final realLoss when realLoss.isNotEmpty)
        _problemSlide(c.source, realLoss),
  ];

  /// De kop boven de notitiedia, die zegt wát er met de dia is gebeurd.
  String? _headingFor(
    SlideFailurePolicy policy,
    int sourceNumber,
  ) => switch (policy) {
    SlideFailurePolicy.bestEffort => null,
    SlideFailurePolicy.skip =>
      '# ${translate('Dia {n} overgeslagen').replaceAll('{n}', '$sourceNumber')}',
    SlideFailurePolicy.imageOnly =>
      '# ${translate('Dia {n}: alleen de afbeelding overgenomen').replaceAll('{n}', '$sourceNumber')}',
  };

  /// Alleen de afbeeldingen van [s], als afbeeldingsdia; de tekst vervalt.
  Slide _imageOnlySlide(SourceSlide s) {
    final base = Slide.create(
      s.images.length >= 2 ? SlideType.twoImages : SlideType.image,
    );
    return base.copyWith(
      title: _safe(s.title),
      imagePath: _memPathFor(s.images.first),
      imagePath2: s.images.length >= 2 ? _memPathFor(s.images[1]) : null,
      imageCaption: _caption(s, 0),
      imageCaption2: s.images.length >= 2 ? _caption(s, 1) : null,
      notes: _notes(s),
      skipped: s.isHidden ? true : null,
    );
  }

  // ── Per-slide construction ─────────────────────────────────────────────────

  Slide _buildSlide(ClassifiedSlide c) {
    final s = c.source;
    final base = Slide.create(c.type);
    final built = switch (c.type) {
      SlideType.title => _title(base, s),
      SlideType.section => _section(base, s),
      SlideType.bullets => _bullets(base, s),
      SlideType.twoBullets => _twoBullets(base, s),
      SlideType.bulletsImage => _bulletsImage(base, s),
      SlideType.twoImages => _twoImages(base, s),
      SlideType.image => _image(base, s),
      SlideType.video => _video(base, s),
      SlideType.quote => _quote(base, s),
      SlideType.table => _table(base, s),
      SlideType.chart => _chart(base, s),
      SlideType.timeline => _timeline(base, s),
      // The classifier only ever picks the types above; anything else is
      // salvaged as free Markdown so no source content is dropped.
      _ => _freeMarkdown(base, s),
    };
    return built.copyWith(
      notes: _notes(s),
      skipped: s.isHidden ? true : null,
      viewLimit: _viewLimitFor(built),
    );
  }

  /// De weergavelimiet voor een zojuist gebouwde dia, of `null` als de inhoud
  /// gewoon past.
  ///
  /// Een bronpresentatie kan een tabel van duizend regels of een lijst van
  /// dertig punten dragen. Zulke data wégsnijden om een leesbare dia te maken
  /// is precies wat OciDeck níét doet (#672): alles blijft in het deck staan en
  /// de dia krijgt een niet-destructieve weergavelimiet, met een telling erbij
  /// zodat zichtbaar is dát er meer is. Wie alles wil tonen, zet de limiet in
  /// de editor uit — de gegevens zijn er nog.
  ///
  /// Bewust `mode: first` (de bronvolgorde) en geen top-N: een importeur heeft
  /// geen grond om te bepalen wat de bélangrijkste rijen zijn, en de
  /// bronvolgorde is wat de auteur bedoelde.
  DisplayWindowSpec? _viewLimitFor(Slide s) {
    if (s.bullets.length > kImportedBulletLimit ||
        s.bullets2.length > kImportedBulletLimit) {
      return const DisplayWindowSpec(limit: kImportedBulletLimit);
    }
    // De eerste rij is de kop; de limiet telt gegevensrijen.
    if (s.tableRows.length - 1 > kImportedTableRowLimit) {
      return const DisplayWindowSpec(limit: kImportedTableRowLimit);
    }
    return null;
  }

  Slide _title(Slide base, SourceSlide s) => base.copyWith(
    title: _safe(s.title),
    subtitle: _safe(s.subtitle),
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
  );

  Slide _section(Slide base, SourceSlide s) {
    final paragraphs = s.bodyBlocks
        .where((b) => b.kind == BodyBlockKind.paragraph)
        .map((b) => _safe(b.text))
        .toList();
    final links = _hyperlinkMarkdown(s);
    final subtitleParts = [
      if (s.subtitle.isNotEmpty) _safe(s.subtitle),
      ...paragraphs,
      ...links,
    ];
    return base.copyWith(
      title: _safe(s.title),
      subtitle: subtitleParts.join('\n'),
    );
  }

  Slide _bullets(Slide base, SourceSlide s) => base.copyWith(
    title: _safe(s.title),
    subtitle: _safe(s.subtitle),
    bullets: _bulletItems(s),
  );

  Slide _twoBullets(Slide base, SourceSlide s) {
    final (left, right) = _twoColumns(s);
    return base.copyWith(
      title: _safe(s.title),
      subtitle: _safe(s.subtitle),
      bullets: left.isEmpty ? const [''] : left,
      bullets2: right.isEmpty ? const [''] : right,
    );
  }

  Slide _bulletsImage(Slide base, SourceSlide s) => base.copyWith(
    title: _safe(s.title),
    subtitle: _safe(s.subtitle),
    bullets: _bulletItems(s),
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
    imageCaption: _caption(s, 0),
  );

  Slide _twoImages(Slide base, SourceSlide s) => base.copyWith(
    title: _safe(s.title),
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images[0]) : null,
    imagePath2: s.images.length >= 2 ? _memPathFor(s.images[1]) : null,
    imageCaption: _caption(s, 0),
    imageCaption2: _caption(s, 1),
  );

  Slide _image(Slide base, SourceSlide s) => base.copyWith(
    title: _safe(s.title),
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
    imageCaption: _caption(s, 0),
  );

  Slide _video(Slide base, SourceSlide s) {
    final v = s.video;
    return base.copyWith(title: _safe(s.title), videoPath: _videoPathFor(v));
  }

  /// Het pad voor [v], of leeg als er geen video is.
  ///
  /// Een URL-video (los bestand, YouTube, Vimeo) is zijn verwijzing. Een
  /// ingebedde video draagt bytes, en die moeten dezelfde weg als een
  /// afbeelding: een `mem:`-pad dat bij opslaan in de `media/`-map van het deck
  /// terechtkomt. Zonder dat schreven we `media/clip.mp4` in het deck terwijl
  /// er nooit een bestand van die naam is weggeschreven — een dood pad, en de
  /// bron was na de import onherstelbaar weg.
  String _videoPathFor(SourceVideo? v) {
    if (v == null) return '';
    final bytes = v.bytes;
    if (bytes == null) return v.ref;
    return _memPathBySha.putIfAbsent(
      'video:${crypto.sha256.convert(bytes)}',
      () => WebAssetStore.put(
        bytes,
        name: normalizeVideoFileName(v.ref.split(RegExp(r'[\\/]')).last),
      ),
    );
  }

  Slide _quote(Slide base, SourceSlide s) {
    final quote = s.bodyBlocks
        .firstWhere(
          (b) => b.kind == BodyBlockKind.quote,
          orElse: () => const BodyBlock(kind: BodyBlockKind.quote, text: ''),
        )
        .text;
    return base.copyWith(quote: _safe(quote), quoteAuthor: _safe(s.title));
  }

  Slide _table(Slide base, SourceSlide s) {
    final t = s.table;
    // Elke cel inline geneutraliseerd: `encodeMarkdownTableCell` dekt de
    // tabelstructuur (`|`/`\`/`<br>`), niet de HTML-/linkinjectie erin (#876).
    final rows = t == null
        ? const <List<String>>[]
        : [_safeRow(t.header), ...t.rows.map(_safeRow)];
    return base.copyWith(title: _safe(s.title), tableRows: rows);
  }

  List<String> _safeRow(List<String> row) => [
    for (final cell in row) sanitizeImportedInline(cell),
  ];

  Slide _chart(Slide base, SourceSlide s) {
    final c = s.chart;
    if (c == null) return base.copyWith(title: _safe(s.title));
    final spec = ChartSpec(
      type: _chartType(c.type),
      title: _safe(c.title),
      x: [for (final label in c.x) _safe(label)],
      rowColors: c.rowColors,
      minBound: c.minBound,
      maxBound: c.maxBound,
      series: [
        for (final series in c.series)
          ChartSeries(
            name: _safe(series.name),
            data: series.data,
            color: series.color,
          ),
      ],
    );
    return base.copyWith(title: _safe(s.title), customMarkdown: spec.toBlock());
  }

  Slide _timeline(Slide base, SourceSlide s) {
    final events = [
      for (final b in s.bodyBlocks)
        if (b.kind == BodyBlockKind.bullet) _timelineEvent(_safe(b.text)),
    ];
    return base.copyWith(
      title: _safe(s.title),
      bullets: events.isEmpty ? base.bullets : timelineEventsToBullets(events),
    );
  }

  Slide _freeMarkdown(Slide base, SourceSlide s) =>
      base.copyWith(customMarkdown: _freeMarkdownBody(s));

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// The bullet items of [s] as OciDeck bullet strings, encoding nesting with
  /// leading tabs (OciDeck's [bulletLevel] convention). Any hyperlinks are
  /// appended as extra bullets so links ride inline with the text. Never empty
  /// (a bullet-backed slide seeds one blank item), matching [Slide.create].
  List<String> _bulletItems(SourceSlide s) {
    final items = [
      for (final b in s.bodyBlocks)
        if (b.kind == BodyBlockKind.bullet) '${'\t' * b.level}${_safe(b.text)}',
      for (final link in _hyperlinkMarkdown(s)) link,
    ];
    return items.isEmpty ? const [''] : items;
  }

  /// Eén opsommingspunt is één regel.
  ///
  /// PowerPoint schrijft een zachte regelafbreking (`<a:br/>`) binnen één
  /// alinea; de importer maakt daar een `\n` van. Die ongewijzigd wegschrijven
  /// brak de lijst: bij het teruglezen werd de vervolgregel de paragraaf van de
  /// dia, en bij een tweede zo'n punt verdween hij helemaal — echte tekst weg,
  /// zonder melding. Samenvoegen tot één regel verliest de *afbreking*, niet de
  /// woorden; dat is de goede kant om op te vallen.
  static String singleLine(String text) =>
      text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

  /// Brontekst voor een **rauw geserialiseerd** veld (titel, kop, bullet, quote,
  /// vrije Markdown), veilig gemaakt tegen Markdown-/HTML-injectie (#876). De
  /// volle sanitizer vouwt ook regels in, dus `singleLine` erbovenop is overbodig.
  static String _safe(String text) => sanitizeImportedText(text);

  /// De notitie van [s], inline geneutraliseerd en met regels behouden, of
  /// `null` als er niets overblijft. Inline en niet vol: de notitie-serialisatie
  /// heeft haar eigen `-->`-escaper en de notitie mag meerregelig blijven.
  String? _notes(SourceSlide s) {
    final trimmed = s.notes.trim();
    return trimmed.isEmpty ? null : sanitizeImportedInline(trimmed);
  }

  List<BodyBlock> _bulletBlocks(SourceSlide s) =>
      s.bodyBlocks.where((b) => b.kind == BodyBlockKind.bullet).toList();

  /// Hyperlinks as inline Markdown link strings (`[text](url)`). The scheme is
  /// neutralised via [_safeUrl] (no `javascript:`), and the link **text** is
  /// inline-geneutraliseerd (#876): HTML uit de brontekst wordt inert en de
  /// haakjes worden ontsnapt, zodat een linktekst geen `<script>` of een tweede
  /// link kan binnensmokkelen.
  List<String> _hyperlinkMarkdown(SourceSlide s) => [
    for (final link in s.hyperlinks)
      '[${sanitizeImportedInline(link.text)}](${_safeUrl(link.url)})',
  ];

  /// Schema's die een link in een geïmporteerd deck niet mag dragen.
  static const _unsafeLinkSchemes = [
    'javascript:',
    'data:',
    'vbscript:',
    'file:',
  ];

  bool _isUnsafeUrl(String url) {
    final lower = url.trim().toLowerCase();
    return _unsafeLinkSchemes.any(lower.startsWith);
  }

  String _safeUrl(String url) {
    final trimmed = url.trim();
    if (_isUnsafeUrl(trimmed)) return 'https://invalid';
    // Percent-encodeer de tekens die uit `[tekst](url)` kunnen breken (#876):
    // witruimte en C0-controltekens — een ingesloten newline smokkelde anders een
    // dia, een tracking-beacon `![](…)` of een directive het deck in, en de
    // backstop zag dat niet (die zoekt alleen uitvoerbare inhoud) — plus `(`/`)`
    // die de link vroegtijdig sluit en `<`/`>` van een autolink. Een echte URL
    // heeft die tekens niet letterlijk; de encodering laat hem gewoon werken.
    return trimmed.replaceAllMapped(_urlBreakoutChar, (m) {
      final code = m[0]!.codeUnitAt(0);
      return '%${code.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    });
  }

  /// Tekens die een link-URL uit `[tekst](url)` kunnen laten breken.
  static final RegExp _urlBreakoutChar = RegExp('[\\s\u0000-\u001f()<>]');

  /// Links waarvan het doel is weggehaald, zodat de notitiedia ze kan noemen.
  ///
  /// Het schema neutraliseren is niet onderhandelbaar — een `javascript:`-link
  /// uit een vreemd bestand hoort niet in het deck van de gebruiker. Maar het
  /// doel spoorloos vervangen door `https://invalid` is dat wél: de linktekst
  /// blijft staan, en de gebruiker kan niet eens zien wát er stond. Voor een
  /// `file:`-verwijzing in een interne presentatie is dat gewone inhoud.
  /// Daarom: neutraliseren én opschrijven.
  List<ConversionIssue> _neutralisedLinkIssues(SourceSlide s) => [
    for (final link in s.hyperlinks)
      if (_isUnsafeUrl(link.url))
        ConversionIssue(
          slideIndex: s.index,
          feature: 'Koppeling “{tekst}”',
          description: 'doel onschadelijk gemaakt; het wees naar {url}',
          salvagedAs: 'de tekst blijft staan, de verwijzing niet',
          // De linktekst en het doel belanden in de notitiedia; die wordt door
          // `UnconvertedTracker._escMarkdown` al geneutraliseerd (HTML, de
          // Markdown-metatekens en regeleinden), dus hier géén tweede escaping —
          // dat leverde alleen `&amp;amp;lt;` op (#876).
          args: {'tekst': link.text, 'url': link.url.trim()},
        ),
  ];

  /// Split a two-column slide into left/right bullet lists. Prefers the raw
  /// positioned text boxes (clustered by x), falling back to halving the
  /// bullets — the same heuristic the classifier used to pick `twoBullets`.
  (List<String>, List<String>) _twoColumns(SourceSlide s) {
    if (s.positionedTexts.length >= 2) {
      final xs = s.positionedTexts.map((p) => p.left).toList()..sort();
      final median = xs[xs.length ~/ 2];
      final left = <String>[];
      final right = <String>[];
      for (final p in s.positionedTexts) {
        (p.left < median ? left : right).add(singleLine(p.text));
      }
      return (left, right);
    }
    final bullets = [for (final b in _bulletBlocks(s)) singleLine(b.text)];
    final mid = bullets.length ~/ 2;
    return (bullets.sublist(0, mid), bullets.sublist(mid));
  }

  TimelineEvent _timelineEvent(String raw) {
    final idx = raw.indexOf('::');
    if (idx < 0) return TimelineEvent(title: raw.trim());
    return TimelineEvent(
      marker: raw.substring(0, idx).trim(),
      title: raw.substring(idx + 2).trim(),
    );
  }

  String _freeMarkdownBody(SourceSlide s) {
    final buf = StringBuffer();
    if (s.title.isNotEmpty) buf.writeln('# ${_safe(s.title)}');
    for (final block in s.bodyBlocks) {
      buf.writeln();
      switch (block.kind) {
        case BodyBlockKind.heading:
          buf.writeln('${'#' * (block.level + 1)} ${_safe(block.text)}');
        case BodyBlockKind.paragraph:
          buf.writeln(_safe(block.text));
        case BodyBlockKind.bullet:
          buf.writeln('${'  ' * block.level}- ${_safe(block.text)}');
        case BodyBlockKind.quote:
          buf.writeln('> ${_safe(block.text)}');
      }
    }
    for (final link in _hyperlinkMarkdown(s)) {
      buf.writeln();
      buf.writeln(link);
    }
    return buf.toString().trim();
  }

  /// Het bijschrift van afbeelding [index], tot één regel gevouwen (#876).
  ///
  /// De caption gaat via de HtmlEscape-serialisatie (HTML-veilig) en de
  /// fail-closed backstop, maar geen enkele importer vult `caption` op dit
  /// moment; `singleLine` sluit alvast het structurele newline-gat dat een
  /// meerregelig bijschrift zou openen (een `---` op een eigen regel breekt uit,
  /// en dat ziet de backstop niet — het is geen uitvoerbare inhoud).
  String _caption(SourceSlide s, int index) =>
      index < s.images.length ? singleLine(s.images[index].caption ?? '') : '';

  /// A stable `mem:` path for [img]'s bytes, reusing one entry per content hash.
  String _memPathFor(SourceImage img) => _memPathBySha.putIfAbsent(
    img.sha256,
    () => WebAssetStore.put(img.bytes, name: _imageName(img)),
  );

  /// A filename for the materialised image: the source name when it carries a
  /// usable extension, otherwise a neutral stem plus the detected extension. The
  /// on-disk de-dup on save keys on this name, so it must end in an extension.
  String _imageName(SourceImage img) {
    final ext = img.ext.trim().isNotEmpty ? img.ext.trim() : 'png';
    final raw = img.name?.trim() ?? '';
    if (raw.isEmpty) return 'afbeelding.$ext';
    final base = raw.split(RegExp(r'[\\/]')).last;
    // Door de witte lijst: een bronarchief bepaalt zijn eigen bijlagenamen, en
    // `rapport.pdf.command` hoort niet in de projectmap van de gebruiker.
    return normalizeImageFileName(base, fallbackExtension: ext);
  }

  ChartType _chartType(SourceChartType t) => switch (t) {
    SourceChartType.bar => ChartType.bar,
    SourceChartType.stackedBar => ChartType.stackedBar,
    SourceChartType.line => ChartType.line,
    SourceChartType.pie => ChartType.pie,
    SourceChartType.radar => ChartType.radar,
    SourceChartType.scatter => ChartType.scatter,
  };

  // ── Conversion-loss notes ──────────────────────────────────────────────────

  /// The conversion issues to note after slide [c]: the classifier's own
  /// per-slide issues plus the builder's structural salvage losses (audio, a
  /// table beside a chart).
  List<ConversionIssue> _conversionIssuesFor(ClassifiedSlide c) => [
    ...c.issues,
    ..._salvageIssues(c.source),
    ..._droppedContentIssues(c),
    ..._neutralisedLinkIssues(c.source),
  ];

  /// Inhoud die de veldafbeelding van het gekozen dia-type laat vallen.
  ///
  /// Dit is de tweede helft van de belofte "niets verdwijnt stil". De
  /// classifier meldt wat híj niet kwijt kan, maar daarna gooit de bouwer zélf
  /// nog dingen weg — een inleidende alinea boven een bullet-lijst, de derde
  /// afbeelding, bullets naast een tabel — en dat gebeurde zonder één woord.
  /// Een gebruiker die zijn dia terugziet zonder die alinea heeft geen enkele
  /// aanwijzing dat de import hem heeft laten vallen.
  ///
  /// De regel is: meld alleen wat dit type werkelijk niet leest. Verlies
  /// mélden dat er niet is, is even schadelijk als het verzwijgen — dan gaat
  /// de gebruiker zoeken naar iets wat gewoon op zijn dia staat.
  List<ConversionIssue> _droppedContentIssues(ClassifiedSlide c) {
    final s = c.source;
    final issues = <ConversionIssue>[];

    int countOf(BodyBlockKind kind) =>
        s.bodyBlocks.where((b) => b.kind == kind).length;

    // Alinea's. Alleen `section` (in de ondertitel) en `freeMarkdown` (in de
    // body) nemen ze mee; `quote` leest uitsluitend het quote-blok.
    const readsParagraphs = {SlideType.section, SlideType.freeMarkdown};
    final paragraphs = countOf(BodyBlockKind.paragraph);
    if (paragraphs > 0 && !readsParagraphs.contains(c.type)) {
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: paragraphs == 1 ? 'Alinea' : '{n} alinea’s',
          description:
              'niet overgenomen (een {type}-dia toont geen losse '
              'alineatekst)',
          args: {'n': '$paragraphs', 'type': c.type.name},
        ),
      );
    }

    // Bullets. Alles wat op een bullet-lijst uitkomt leest ze; de rest niet.
    const readsBullets = {
      SlideType.bullets,
      SlideType.twoBullets,
      SlideType.bulletsImage,
      SlideType.timeline,
      SlideType.freeMarkdown,
    };
    final bullets = countOf(BodyBlockKind.bullet);
    if (bullets > 0 && !readsBullets.contains(c.type)) {
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: bullets == 1 ? '{n} opsommingspunt' : '{n} opsommingspunten',
          description:
              'niet overgenomen (deze dia werd een {type}, en die '
              'draagt geen opsomming)',
          args: {'n': '$bullets', 'type': c.type.name},
        ),
      );
    }

    // Afbeeldingen voorbij wat het type toont.
    final shown = switch (c.type) {
      SlideType.twoImages => 2,
      SlideType.image || SlideType.bulletsImage || SlideType.title => 1,
      // freeMarkdown lijkt alles te dragen, maar `_freeMarkdownBody` schrijft
      // alleen tekst, koppen en links — geen afbeeldingen. Dus: nul.
      _ => 0,
    };
    if (s.images.length > shown) {
      final extra = s.images.length - shown;
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: extra == 1 ? '{n} afbeelding' : '{n} afbeeldingen',
          description: shown == 0
              ? 'niet overgenomen (deze dia werd een {type})'
              : 'niet overgenomen (een {type}-dia toont er {aantal})',
          args: {'n': '$extra', 'type': c.type.name, 'aantal': '$shown'},
        ),
      );
    }

    return issues;
  }

  /// Losses that OciDeck's model cannot represent, so the note slide can name
  /// them. Ported from Keiko's pipeline salvage checks.
  List<ConversionIssue> _salvageIssues(SourceSlide s) {
    final issues = <ConversionIssue>[];
    if (s.audioFileName != null) {
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: 'Audio "{bestand}"',
          description: 'niet overgenomen (OciDeck heeft geen audio-slides)',
          args: {'bestand': s.audioFileName!},
        ),
      );
    }
    if (s.chart != null && s.table != null) {
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: 'Tabel naast grafiek',
          description: 'niet overgenomen (één grafiek of tabel per slide)',
        ),
      );
    }
    return issues;
  }

  Slide _noteSlide(
    int sourceNumber,
    List<ConversionIssue> issues, {
    String? heading,
  }) => Slide.create(SlideType.freeMarkdown).copyWith(
    customMarkdown: UnconvertedTracker.buildNoteBody(
      sourceNumber,
      issues,
      heading: heading,
      translate: translate,
    ),
  );

  Slide _deckNoteSlide(List<ConversionIssue> issues) =>
      Slide.create(SlideType.freeMarkdown).copyWith(
        customMarkdown: UnconvertedTracker.buildDeckNoteBody(
          issues,
          translate: translate,
        ),
      );

  ProblemSlide _problemSlide(SourceSlide s, List<ConversionIssue> realLoss) =>
      ProblemSlide(
        sourceSlideNumber: s.index + 1,
        title: s.title.isNotEmpty ? s.title : null,
        issueDescriptions: [
          for (final i in realLoss) '${i.feature}: ${i.description}',
        ],
        hadImage: s.images.isNotEmpty,
      );
}
