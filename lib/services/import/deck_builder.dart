import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../web_asset_store.dart';
import 'models/body_block.dart';
import 'models/conversion_issue.dart';
import 'models/slide_failure_policy.dart';
import 'models/source_chart.dart';
import 'models/source_deck.dart';
import 'models/source_image.dart';
import 'models/source_slide.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'pipeline/unconverted_tracker.dart';

/// Hoeveel items een geïmporteerde dia standaard tóónt voordat de
/// weergavelimiet ingrijpt. Ruim genoeg voor een gewone dia, krap genoeg om een
/// duizendregelige brontabel niet onleesbaar te laten worden (#672).
const kImportedBulletLimit = 8;
const kImportedTableRowLimit = 12;

/// The outcome of building an OciDeck [Deck] from a classified source deck: the
/// deck itself plus the [ProblemSlide]s that carried real (non-salvaged) loss,
/// which the UI surfaces for a per-slide decision.
class BuiltDeck {
  const BuiltDeck({required this.deck, required this.problemSlides});

  final Deck deck;
  final List<ProblemSlide> problemSlides;
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
  /// `mem:` path per image content hash, so identical images share one entry.
  final Map<String, String> _memPathBySha = {};

  /// Build an OciDeck [Deck] from [sourceDeck] and its [classified] slides
  /// (aligned by order). [title] becomes the deck title.
  BuiltDeck build(
    SourceDeck sourceDeck,
    List<ClassifiedSlide> classified, {
    required String title,
  }) {
    final slides = <Slide>[];
    final problemSlides = <ProblemSlide>[];

    for (final c in classified) {
      slides.add(_buildSlide(c));

      final issues = _conversionIssuesFor(c);
      if (issues.isNotEmpty) {
        slides.add(_noteSlide(c.source.index + 1, issues));
      }
      final realLoss = issues.where((i) => !i.isSalvaged).toList();
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
      notes: s.notes.trim().isNotEmpty ? s.notes.trim() : null,
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
    title: s.title,
    subtitle: s.subtitle,
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
  );

  Slide _section(Slide base, SourceSlide s) {
    final paragraphs = s.bodyBlocks
        .where((b) => b.kind == BodyBlockKind.paragraph)
        .map((b) => b.text)
        .toList();
    final links = _hyperlinkMarkdown(s);
    final subtitleParts = [
      if (s.subtitle.isNotEmpty) s.subtitle,
      ...paragraphs,
      ...links,
    ];
    return base.copyWith(title: s.title, subtitle: subtitleParts.join('\n'));
  }

  Slide _bullets(Slide base, SourceSlide s) => base.copyWith(
    title: s.title,
    subtitle: s.subtitle,
    bullets: _bulletItems(s),
  );

  Slide _twoBullets(Slide base, SourceSlide s) {
    final (left, right) = _twoColumns(s);
    return base.copyWith(
      title: s.title,
      subtitle: s.subtitle,
      bullets: left.isEmpty ? const [''] : left,
      bullets2: right.isEmpty ? const [''] : right,
    );
  }

  Slide _bulletsImage(Slide base, SourceSlide s) => base.copyWith(
    title: s.title,
    subtitle: s.subtitle,
    bullets: _bulletItems(s),
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
    imageCaption: _caption(s, 0),
  );

  Slide _twoImages(Slide base, SourceSlide s) => base.copyWith(
    title: s.title,
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images[0]) : null,
    imagePath2: s.images.length >= 2 ? _memPathFor(s.images[1]) : null,
    imageCaption: _caption(s, 0),
    imageCaption2: _caption(s, 1),
  );

  Slide _image(Slide base, SourceSlide s) => base.copyWith(
    title: s.title,
    imagePath: s.images.isNotEmpty ? _memPathFor(s.images.first) : null,
    imageCaption: _caption(s, 0),
  );

  Slide _video(Slide base, SourceSlide s) {
    final v = s.video;
    return base.copyWith(title: s.title, videoPath: v?.ref ?? '');
  }

  Slide _quote(Slide base, SourceSlide s) {
    final quote = s.bodyBlocks
        .firstWhere(
          (b) => b.kind == BodyBlockKind.quote,
          orElse: () => const BodyBlock(kind: BodyBlockKind.quote, text: ''),
        )
        .text;
    return base.copyWith(quote: quote, quoteAuthor: s.title);
  }

  Slide _table(Slide base, SourceSlide s) {
    final t = s.table;
    final rows = t == null ? const <List<String>>[] : [t.header, ...t.rows];
    return base.copyWith(title: s.title, tableRows: rows);
  }

  Slide _chart(Slide base, SourceSlide s) {
    final c = s.chart;
    if (c == null) return base.copyWith(title: s.title);
    final spec = ChartSpec(
      type: _chartType(c.type),
      title: c.title,
      x: c.x,
      rowColors: c.rowColors,
      minBound: c.minBound,
      maxBound: c.maxBound,
      series: [
        for (final series in c.series)
          ChartSeries(
            name: series.name,
            data: series.data,
            color: series.color,
          ),
      ],
    );
    return base.copyWith(title: s.title, customMarkdown: spec.toBlock());
  }

  Slide _timeline(Slide base, SourceSlide s) {
    final events = [
      for (final b in s.bodyBlocks)
        if (b.kind == BodyBlockKind.bullet) _timelineEvent(b.text),
    ];
    return base.copyWith(
      title: s.title,
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
        if (b.kind == BodyBlockKind.bullet) '${'\t' * b.level}${b.text}',
      for (final link in _hyperlinkMarkdown(s)) link,
    ];
    return items.isEmpty ? const [''] : items;
  }

  List<BodyBlock> _bulletBlocks(SourceSlide s) =>
      s.bodyBlocks.where((b) => b.kind == BodyBlockKind.bullet).toList();

  /// Hyperlinks as inline Markdown link strings (`[text](url)`), skipping any
  /// with a dangerous scheme so a source link cannot smuggle in `javascript:`.
  List<String> _hyperlinkMarkdown(SourceSlide s) => [
    for (final link in s.hyperlinks) '[${link.text}](${_safeUrl(link.url)})',
  ];

  String _safeUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('vbscript:') ||
        lower.startsWith('file:')) {
      return 'https://invalid';
    }
    return url.trim();
  }

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
        (p.left < median ? left : right).add(p.text);
      }
      return (left, right);
    }
    final bullets = [for (final b in _bulletBlocks(s)) b.text];
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
    if (s.title.isNotEmpty) buf.writeln('# ${s.title}');
    for (final block in s.bodyBlocks) {
      buf.writeln();
      switch (block.kind) {
        case BodyBlockKind.heading:
          buf.writeln('${'#' * (block.level + 1)} ${block.text}');
        case BodyBlockKind.paragraph:
          buf.writeln(block.text);
        case BodyBlockKind.bullet:
          buf.writeln('${'  ' * block.level}- ${block.text}');
        case BodyBlockKind.quote:
          buf.writeln('> ${block.text}');
      }
    }
    for (final link in _hyperlinkMarkdown(s)) {
      buf.writeln();
      buf.writeln(link);
    }
    return buf.toString().trim();
  }

  String _caption(SourceSlide s, int index) =>
      index < s.images.length ? (s.images[index].caption ?? '') : '';

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
    return base.contains('.') ? base : '$base.$ext';
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
    for (final text in c.issues) _issueFromString(c.source.index, text),
    ..._salvageIssues(c.source),
  ];

  /// Losses that OciDeck's model cannot represent, so the note slide can name
  /// them. Ported from Keiko's pipeline salvage checks.
  List<ConversionIssue> _salvageIssues(SourceSlide s) {
    final issues = <ConversionIssue>[];
    if (s.audioFileName != null) {
      issues.add(
        ConversionIssue(
          slideIndex: s.index,
          feature: 'Audio "${s.audioFileName}"',
          description: 'niet overgenomen (OciDeck heeft geen audio-slides)',
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

  ConversionIssue _issueFromString(int index, String text) => ConversionIssue(
    slideIndex: index,
    feature: text.split(' — ').first,
    description: text.contains(' — ')
        ? text.split(' — ').last
        : 'niet overgenomen',
  );

  Slide _noteSlide(int sourceNumber, List<ConversionIssue> issues) =>
      Slide.create(SlideType.freeMarkdown).copyWith(
        customMarkdown: UnconvertedTracker.buildNoteBody(sourceNumber, issues),
      );

  Slide _deckNoteSlide(List<ConversionIssue> issues) => Slide.create(
    SlideType.freeMarkdown,
  ).copyWith(customMarkdown: UnconvertedTracker.buildDeckNoteBody(issues));

  ProblemSlide _problemSlide(SourceSlide s, List<ConversionIssue> realLoss) =>
      ProblemSlide(
        sourceSlideNumber: s.index + 1,
        title: s.title.isNotEmpty ? s.title : null,
        issueDescriptions: [
          for (final i in realLoss) '${i.feature}: ${i.description}',
        ],
        hadImage: s.images.isNotEmpty,
        suggestedPolicy: s.images.isNotEmpty
            ? SlideFailurePolicy.rasterize
            : SlideFailurePolicy.bestEffort,
      );
}
