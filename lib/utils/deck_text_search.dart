import '../models/asset_overview_spec.dart';
import '../models/checklist_spec.dart';
import '../models/control_status_spec.dart';
import '../models/discoveries_spec.dart';
import '../models/finding_spec.dart';
import '../models/scorecard_spec.dart';
import '../models/scope_matrix_spec.dart';
import '../models/timeline.dart';
import '../services/improvement/canvas_slide.dart';
import '../services/improvement/canvas_spec.dart';
import '../services/improvement/flow_slide.dart';
import '../services/menu_blocks.dart';
import 'page_scoped_notes.dart';
import '../models/chart.dart';
import '../models/cockpit.dart';
import '../models/deck.dart';
import '../models/question.dart';
import '../models/slide.dart';
import 'text_search.dart';

/// Eén voorkomen met blijvende dia-identiteit en een bereik in het eigen veld.
class DeckTextMatch {
  const DeckTextMatch({
    required this.slideId,
    required this.slideIndex,
    required this.fieldId,
    required this.fieldLabel,
    required this.text,
    required this.range,
    required this.context,
    this.isNotes = false,
  });

  final String slideId;
  final int slideIndex;
  final String fieldId;
  final String fieldLabel;
  final String text;
  final TextMatchRange range;
  final String context;
  final bool isNotes;

  String get identity => '$slideId/$fieldId/${range.start}/${range.end}';
}

typedef DeckTextField = ({
  String id,
  String label,
  String text,
  bool literal,
  List<TextMatchRange>? visibleRanges,
});

/// Alleen de velden die deze diavorm werkelijk gebruikt zijn doorzoekbaar.
/// Restvelden blijven bij een typewissel bewaard, maar zijn geen zichtbare tekst.
Iterable<DeckTextField> slideTextFields(
  Slide s, {
  bool includeNotes = false,
}) sync* {
  if (s.type != SlideType.finding &&
      s.type != SlideType.freeMarkdown &&
      s.type != SlideType.quote &&
      s.type != SlideType.chart) {
    yield _field('title', 'Titel', s.title);
  }
  if (s.type.isHeading || s.type == SlideType.bullets) {
    yield _field('subtitle', 'Subtitel', s.subtitle);
  }
  final richBody =
      (s.type == SlideType.bullets || s.type == SlideType.bulletsImage) &&
      s.listStyle == ListStyle.richText;
  if ((!richBody && s.type.bulletColumns != BulletColumns.none) ||
      s.type == SlideType.tree ||
      s.type == SlideType.flow) {
    if (s.type.bulletColumns == BulletColumns.two) {
      yield _field('columnTitle1', 'Kop', s.columnTitle1);
    }
    for (var i = 0; i < s.bullets.length; i++) {
      final text = _bulletText(s.bullets[i]);
      if (s.type == SlideType.flow) {
        // Alleen titel en baan worden getekend; kind/attrs zijn machinesyntax.
        final step = parseFlowBullet(s.bullets[i]);
        yield _field(
          'bullets.$i',
          'Bullets links',
          text,
          visibleRanges: _flowTextRanges(text, step.title, step.lane),
        );
      } else {
        yield _field('bullets.$i', 'Bullets links', text);
      }
    }
    if (s.type.bulletColumns == BulletColumns.two) {
      yield _field('columnTitle2', 'Kop', s.columnTitle2);
      for (var i = 0; i < s.bullets2.length; i++) {
        yield _field(
          'bullets2.$i',
          'Bullets rechts',
          _bulletText(s.bullets2[i]),
        );
      }
    }
  }
  if (s.type == SlideType.quote) {
    yield _field('quote', 'Citaat', s.quote);
    yield _field('quoteAuthor', 'Auteur', s.quoteAuthor);
  }
  if (const {
    SlideType.title,
    SlideType.image,
    SlideType.twoImages,
    SlideType.bulletsImage,
    SlideType.question,
  }.contains(s.type)) {
    yield _field('imageCaption', 'Bijschrift', s.imageCaption);
    if (s.type == SlideType.twoImages || s.type == SlideType.title) {
      yield _field('imageCaption2', 'Bijschrift', s.imageCaption2);
    }
  }
  yield* _tableFields(s);
  yield* _bodyFields(s);
  if (includeNotes) {
    final pages = parsePageScopedNotes(s.notes).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final page in pages) {
      yield _field('notes.${page.key}', 'Sprekersnotities', page.value);
    }
  }
}

DeckTextField _field(
  String id,
  String label,
  String text, {
  bool literal = false,
  List<TextMatchRange>? visibleRanges,
}) => (
  id: id,
  label: label,
  text: text,
  literal: literal,
  visibleRanges: visibleRanges,
);

String _bulletText(String raw) =>
    isGroupHeading(raw) ? groupHeadingText(raw) : checklistItemText(raw);

List<TextMatchRange> _flowTextRanges(String raw, String title, String lane) {
  final laneKey = RegExp(r'lane\s*=\s*', caseSensitive: false).firstMatch(raw);
  final laneStart = laneKey == null || lane.isEmpty
      ? -1
      : raw.indexOf(lane, laneKey.end);
  return [
    if (title.isNotEmpty && raw.contains(title))
      TextMatchRange(raw.indexOf(title), raw.indexOf(title) + title.length),
    if (laneStart >= 0) TextMatchRange(laneStart, laneStart + lane.length),
  ];
}

Iterable<DeckTextField> _tableFields(Slide s) sync* {
  if (!s.type.backedByTable) return;
  final rows = switch (s.type) {
    SlideType.scorecard => ScorecardSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    SlideType.assets => AssetOverviewSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    SlideType.discoveries => DiscoveriesSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    SlideType.checklist => ChecklistSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    SlideType.scopeMatrix => ScopeMatrixSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    SlideType.controlStatus => ControlStatusSpec.fromSlide(
      s.title,
      s.tableRows,
    ).toTableRows(),
    _ => s.tableRows,
  };
  final columns = switch (s.type) {
    SlideType.scorecard => const {0, 1, 2, 3},
    SlideType.checklist => const {0, 1, 3, 4},
    SlideType.scopeMatrix => const {0, 4},
    SlideType.controlStatus => const {0, 1, 4, 5, 6, 7},
    SlideType.findingsSummary => const <int>{},
    SlideType.gantt => const {0},
    _ => null,
  };
  for (var r = s.type == SlideType.table ? 0 : 1; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      if (columns != null && !columns.contains(c)) continue;
      final cell = rows[r][c];
      final prefix = s.type == SlideType.gantt && cell.startsWith('Milestone: ')
          ? 'Milestone: '.length
          : 0;
      yield _field(
        'tableRows.$r.$c',
        'Tabel',
        cell,
        visibleRanges: prefix == 0
            ? null
            : [TextMatchRange(prefix, cell.length)],
      );
    }
  }
}

Iterable<DeckTextField> _bodyFields(Slide s) sync* {
  DeckTextField field(String id, String text, {bool literal = false}) =>
      _field(id, s.type.label, text, literal: literal);
  switch (s.type) {
    case SlideType.timeline:
      final events = parseTimelineEvents(s.bullets);
      for (var i = 0; i < events.length; i++) {
        yield field('timeline.$i.marker', events[i].marker);
        yield field('timeline.$i.title', events[i].title);
        yield field('timeline.$i.description', events[i].description);
      }
    case SlideType.menu:
      final categories = menuCategoriesFor(s.bullets);
      var block = 0;
      for (var c = 0; c < categories.length; c++) {
        yield field('menuCategory.$c', categories[c].label);
        for (final item in categories[c].blocks) {
          yield field('menu.$block.label', item.label);
          yield field('menu.$block.description', item.description);
          block++;
        }
      }
    case SlideType.canvas:
      final templateId = s.improvementTemplateId.isEmpty
          ? kDefaultCanvasTemplateId
          : s.improvementTemplateId;
      for (final region in canvasRegionsFromMarkdown(
        s.customMarkdown,
        templateId: templateId,
      )) {
        if (canvasTemplateById(templateId) == null) {
          yield field('canvas.${region.key}.heading', region.heading);
        }
        yield field('canvas.${region.key}.body', region.body);
      }
    case SlideType.finding:
      yield* _findingFields(FindingSpec.parse(s.customMarkdown));
    case SlideType.chart:
      final spec = ChartSpec.parse(s.customMarkdown);
      yield field('chart.title', spec.title, literal: true);
      for (var i = 0; i < spec.x.length; i++) {
        yield field('chart.x.$i', spec.x[i], literal: true);
      }
      for (var i = 0; i < spec.series.length; i++) {
        yield field('chart.series.$i', spec.series[i].name, literal: true);
      }
    case SlideType.cockpit:
      final spec = CockpitSpec.parse(s.customMarkdown);
      for (var i = 0; i < spec.meters.length; i++) {
        final m = spec.meters[i];
        yield field('cockpit.$i.label', m.label, literal: true);
        yield field('cockpit.$i.unit', m.unit, literal: true);
        yield field('cockpit.$i.markerLabel', m.markerLabel, literal: true);
      }
    case SlideType.question:
      yield* _questionFields(QuestionSpec.parse(s.customMarkdown));
    case SlideType.code:
      yield field('customMarkdown', s.customMarkdown, literal: true);
    case SlideType.title:
    case SlideType.freeMarkdown:
    case SlideType.objective:
    case SlideType.module:
    case SlideType.feedback:
    case SlideType.assessmentSummary:
      yield field('customMarkdown', s.customMarkdown);
    case SlideType.bullets:
    case SlideType.bulletsImage:
      if (s.listStyle == ListStyle.richText) {
        yield field('customMarkdown', s.customMarkdown);
      }
    default:
      break;
  }
}

Iterable<DeckTextField> _findingFields(FindingSpec spec) sync* {
  for (final entry in {
    'heading': spec.heading,
    'scopeObject': spec.scopeObject,
    'cvssVector': spec.cvssVector,
    'cwe': spec.cweId == null
        ? ''
        : 'CWE-${spec.cweId}${spec.cweName.isEmpty ? '' : ' — ${spec.cweName}'}',
    'cveIds': spec.cveIds.join(', '),
    'masweId': spec.masweId,
    'description': spec.description,
    'confirmation': spec.confirmation,
    'impact': spec.impact,
    'recommendation': spec.recommendation,
    'retestNote': spec.retestNote,
    'testId': spec.testId,
  }.entries) {
    yield _field('finding.${entry.key}', 'Bevinding', entry.value);
  }
}

Iterable<DeckTextField> _questionFields(QuestionSpec spec) sync* {
  DeckTextField field(String id, String text) =>
      _field('question.$id', 'Vraag', text);
  yield field('prompt', spec.prompt);
  // Open tekst bewaart juiste antwoorden als sleutel, niet als getoonde opties.
  if (const {
    QuestionKind.multipleChoice,
    QuestionKind.multipleCorrect,
    QuestionKind.ordering,
    QuestionKind.imagePair,
  }.contains(spec.kind)) {
    for (var i = 0; i < spec.answers.length; i++) {
      yield field('answers.$i', spec.answers[i].text);
    }
  }
  if (spec.kind == QuestionKind.matching) {
    for (var i = 0; i < spec.pairs.length; i++) {
      yield field('pairs.$i.left', spec.pairs[i].left);
      yield field('pairs.$i.right', spec.pairs[i].right);
    }
    for (var i = 0; i < spec.distractors.length; i++) {
      yield field('distractors.$i', spec.distractors[i]);
    }
  }
  if (spec.kind == QuestionKind.hotspot) {
    for (var i = 0; i < spec.regions.length; i++) {
      yield field('regions.$i', spec.regions[i].label);
    }
  }
  if (spec.kind == QuestionKind.fillIn) {
    for (var i = 0; i < spec.fields.length; i++) {
      yield field('fields.$i', spec.fields[i].placeholder);
      yield field('fields.$i.unit', spec.fields[i].unit);
    }
  }
  yield field('hints', spec.hints.join('\n'));
  for (final entry in {
    'correct': spec.feedback.correct,
    'wrong': spec.feedback.wrong,
    'partial': spec.feedback.partial,
    'timeout': spec.feedback.timeout,
  }.entries) {
    yield field('feedback.${entry.key}', entry.value);
  }
}

List<DeckTextMatch> searchDeckText(
  Deck deck,
  String query, {
  bool caseSensitive = false,
  bool includeNotes = false,
}) {
  if (query.isEmpty) return const [];
  final result = <DeckTextMatch>[];
  for (var i = 0; i < deck.slides.length; i++) {
    for (final field in slideTextFields(
      deck.slides[i],
      includeNotes: includeNotes,
    )) {
      if (field.text.isEmpty) continue;
      final projection = field.literal ? null : VisibleMarkdownText(field.text);
      final visible = projection?.text ?? field.text;
      for (final match in findAllMatches(
        visible,
        query,
        caseSensitive: caseSensitive,
      )) {
        final range = projection == null
            ? match
            : TextMatchRange(
                projection.offsets[match.start],
                projection.offsets[match.end - 1] + 1,
              );
        final allowed = field.visibleRanges;
        if (allowed != null &&
            !allowed.any((r) => range.start >= r.start && range.end <= r.end)) {
          continue;
        }
        result.add(
          DeckTextMatch(
            slideId: deck.slides[i].id,
            slideIndex: i,
            fieldId: field.id,
            fieldLabel: field.label,
            text: field.text,
            range: range,
            context: allowed == null
                ? projection?.context(range) ??
                      _literalContext(field.text, range)
                : allowed
                      .map(
                        (r) => visibleMarkdownText(
                          field.text.substring(r.start, r.end),
                        ),
                      )
                      .join(' · '),
            isNotes: field.id.startsWith('notes.'),
          ),
        );
      }
    }
  }
  return result;
}

String _literalContext(String text, TextMatchRange range) {
  final from = (range.start - 45).clamp(0, text.length);
  final to = (range.end + 45).clamp(from, text.length);
  return '${from > 0 ? '…' : ''}${text.substring(from, to)}${to < text.length ? '…' : ''}';
}
