import '../../../models/body_block.dart';
import '../../../models/conversion_issue.dart';
import '../../../models/source_chart.dart';
import '../../../models/source_image.dart';
import '../../../models/source_slide.dart';
import '../../../models/source_table.dart';
import '../../../models/source_video.dart';
import '../../../pipeline/parse_guard.dart';
import '../key_context.dart';
import 'chart_reconstructor.dart';
import 'drawable_reader.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'media_reconstructor.dart';
import 'slide_order.dart';
import 'table_reconstructor.dart';

/// Schema-aware reconstruction of [SourceSlide]s from an iWork object graph,
/// using the public iWork proto field layouts (obriensp/iWorkFileFormat):
///
/// - `KN.DocumentArchive.show` (field 2) -> `KN.ShowArchive.slideTree` (field 3)
///   -> `KN.SlideTreeArchive.rootSlideNode` (field 1) -> `KN.SlideNodeArchive`
///   (`children` = field 1 repeated Reference, `slide` = field 2 Reference).
///   The SlideNode tree is walked depth-first to recover the **real slide
///   order**; each node's `slide` ref points at a `KN.SlideArchive`.
/// - `KN.SlideArchive`: `titlePlaceholder` (5), `bodyPlaceholder` (6),
///   `drawables` (7, repeated Reference), `name` (10).
/// - `TSWP.ShapeInfoArchive`: `super` = ShapeArchive (field 1, submessage),
///   `containedStorage` (field 2, Reference) -> a StorageArchive.
/// - `TSWP.StorageArchive`: `text` (field 3, repeated string).
/// - `TSD.GroupArchive`: `children` (field 2, repeated Reference).
///
/// Apple's runtime `TSPRegistry` (typeId -> class) is not available, so message
/// types are detected **structurally** from their field shapes and reference
/// targets. When the SlideNode tree cannot be found, slides are emitted in
/// parse (insertion) order as a best-effort fallback.
///
/// The assembler here delegates two responsibilities to collaborators (#878):
/// discovering the slide order to [SlideOrder], and reconstructing the text and
/// drawable structure of one slide to [DrawableReader]; the table, chart and
/// media reconstructors were already separate.
class SlideReconstructor {
  SlideReconstructor(this.doc, {this.ctx});

  final IwaDocument doc;
  final KeyContext? ctx;

  /// Conversion issues raised while reconstructing this deck.
  final List<ConversionIssue> issues = [];

  late final _tableReconstructor = TableReconstructor(doc);
  late final _chartReconstructor = ChartReconstructor(doc);
  late final _mediaReconstructor = MediaReconstructor(doc, ctx: ctx);
  late final _slideOrder = SlideOrder(doc);
  late final _drawableReader = DrawableReader(doc, ctx: ctx);

  /// Reconstruct slides in source order. Text-bearing slides are returned as
  /// bullet slides; image-only slides are also returned, carrying the `Data/`
  /// image when [ctx] is available. Table-, chart- and media-bearing slides are
  /// also returned.
  List<SourceSlide> reconstruct() {
    issues.clear();
    final ordered = _slideOrder.orderedSlideObjects();
    final slides = <SourceSlide>[];
    for (var pos = 0; pos < ordered.length; pos++) {
      final obj = ordered[pos];
      // Isoleer een onverwachte fout tot déze dia (#877): één beschadigd
      // slide-object mag de reconstructie van de rest niet afbreken. Het verlies
      // gaat naar de deckbrede notitie via `issues`.
      guardParseVoid(
        sink: issues,
        slideIndex: pos,
        component: IssueComponent.slide,
        feature: 'Dia-inhoud',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'KeyImporter: dia ${pos + 1}',
        body: () {
          final content = _slideContent(obj, pos);
          if (content.text == null &&
              content.images.isEmpty &&
              content.table == null &&
              content.chart == null &&
              content.video == null &&
              content.audioFileName == null) {
            return; // blank — nothing to salvage.
          }
          slides.add(_buildSlide(obj, pos, content));
        },
      );
    }
    return slides;
  }

  /// The text, images, table, chart and media recovered from a slide. [text]
  /// is `null` when the slide has no text; [images] is empty when it has no
  /// images.
  ({
    String? text,
    List<SourceImage> images,
    SourceTable? table,
    SourceChart? chart,
    SourceVideo? video,
    String? audioFileName,
    List<ConversionIssue> issues,
  })
  _slideContent(IwaObject o, int slideIndex) {
    final title =
        _drawableReader.placeholderTextWithLevels(o, 5) ??
        o.message.string(10) ??
        '';
    final body = <String>[];
    final images = <SourceImage>[];
    final localIssues = <ConversionIssue>[];
    SourceTable? table;
    SourceChart? chart;
    SourceVideo? video;
    String? audioFileName;
    final bodyPlaceholder = _drawableReader.placeholderTextWithLevels(o, 6);
    if (bodyPlaceholder != null) body.add(bodyPlaceholder);
    final (drawables, hadGroup) = _drawableReader.flattenDrawables(
      doc.resolveReferences(o, 7),
    );
    if (hadGroup) {
      localIssues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Groepering',
          description:
              'Gegroepeerde objecten zijn uitgeklapt; groepering en '
              'volgorde binnen de groep gaan verloren.',
          salvagedAs: 'objecten apart overgenomen',
        ),
      );
    }
    for (final drawable in drawables) {
      final drawableImages = _drawableReader.imagesForDrawable(drawable);
      images.addAll(drawableImages);
      final tableResult = _tableForDrawable(drawable, slideIndex);
      if (tableResult != null) {
        if (table == null) {
          table = tableResult;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere tabellen',
              description:
                  'Dia bevat meerdere tabellen; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste tabel overgenomen',
            ),
          );
        }
      }
      final chartResult = _chartForDrawable(drawable, slideIndex);
      if (chartResult != null) {
        if (chart == null) {
          chart = chartResult;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere grafieken',
              description:
                  'Dia bevat meerdere grafieken; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste grafiek overgenomen',
            ),
          );
        }
      }
      final media = _mediaForDrawable(drawable, slideIndex);
      if (media.video != null) {
        if (video == null) {
          video = media.video;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere video\'s',
              description:
                  'Dia bevat meerdere video\'s; OciDeck ondersteunt er '
                  'maar één per dia.',
              salvagedAs: 'eerste video overgenomen',
            ),
          );
        }
      }
      if (media.audioFileName != null) {
        if (audioFileName == null) {
          audioFileName = media.audioFileName;
        } else {
          localIssues.add(
            ConversionIssue(
              slideIndex: slideIndex,
              feature: 'Meerdere audio',
              description:
                  'Dia bevat meerdere audiofragmenten; OciDeck ondersteunt '
                  'er maar één per dia.',
              salvagedAs: 'eerste audio overgenomen',
            ),
          );
        }
      }
      final t = _drawableReader.shapeTextWithLevels(drawable);
      if (t != null && t != title && t != bodyPlaceholder) body.add(t);
      if (_drawableReader.isUnhandledDrawable(
        drawable,
        t,
        drawableImages,
        tableResult,
        chartResult,
        media,
      )) {
        localIssues.add(
          ConversionIssue(
            slideIndex: slideIndex,
            feature: 'Vorm of object',
            description:
                'Een niet-tekstuele vorm, lijn of ander object kon niet '
                'worden omgezet.',
            salvagedAs: 'overgeslagen',
          ),
        );
      }
    }
    issues.addAll(localIssues);
    final String? text;
    if (title.trim().isEmpty && body.every((b) => b.trim().isEmpty)) {
      text = null;
    } else {
      text = body.isEmpty ? title : '$title\n${body.join('\n')}';
    }
    return (
      text: text,
      images: images,
      table: table,
      chart: chart,
      video: video,
      audioFileName: audioFileName,
      issues: localIssues,
    );
  }

  SourceSlide _buildSlide(
    IwaObject o,
    int index,
    ({
      String? text,
      List<SourceImage> images,
      SourceTable? table,
      SourceChart? chart,
      SourceVideo? video,
      String? audioFileName,
      List<ConversionIssue> issues,
    })
    content,
  ) {
    final notes = _drawableReader.notesText(o);
    final title = content.text == null
        ? (o.message.string(10)?.trim() ?? '')
        : content.text!.split(RegExp(r'\r\n|\r|\n')).first.trim();
    final blocks = <BodyBlock>[];
    if (content.text != null) {
      var order = 0;
      for (final line in content.text!.split(RegExp(r'\r\n|\r|\n')).skip(1)) {
        // Leading tabs encode the bullet indent level (see
        // DrawableReader.shapeTextWithLevels). Count them before trimming.
        var level = 0;
        while (level < line.length && line[level] == '\t') {
          level++;
        }
        final t = line.substring(level).trim();
        if (t.isEmpty) continue;
        blocks.add(
          BodyBlock(
            kind: BodyBlockKind.bullet,
            text: t,
            level: level,
            order: order++,
          ),
        );
      }
    }
    return SourceSlide(
      index: index,
      title: title,
      bodyBlocks: blocks,
      images: content.images,
      table: content.table,
      chart: content.chart,
      video: content.video,
      audioFileName: content.audioFileName,
      notes: notes ?? '',
    );
  }

  /// The table contained by a drawable, if this drawable is a `TableInfoArchive`.
  SourceTable? _tableForDrawable(IwaObject o, int slideIndex) {
    final table = _tableReconstructor.reconstruct(o, slideIndex);
    issues.addAll(_tableReconstructor.issues);
    return table;
  }

  /// The chart contained by a drawable, if this drawable is a `ChartDrawableArchive`.
  SourceChart? _chartForDrawable(IwaObject o, int slideIndex) {
    final chart = _chartReconstructor.reconstruct(o, slideIndex);
    issues.addAll(_chartReconstructor.issues);
    return chart;
  }

  /// The media (video or audio) contained by a drawable, if this drawable is a
  /// `TSD.MovieArchive`.
  ({SourceVideo? video, String? audioFileName}) _mediaForDrawable(
    IwaObject o,
    int slideIndex,
  ) {
    return _mediaReconstructor.extract(o, slideIndex);
  }
}
