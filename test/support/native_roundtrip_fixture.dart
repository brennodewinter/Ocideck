// Authored input, independent of serialization: every type and persistent field
// is compared after a new app process opens the files (#3208).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/asset_overview_spec.dart';
import 'package:ocideck/models/discoveries_spec.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/control_status_spec.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/project_path.dart';

import '../slide_fixtures.dart';
import 'persistence_roundtrip_cases.dart';

Set<String> get nativePersistentFields => slideRoundtripCases.keys.toSet();

Deck nativeRoundtripFixture(String projectPath) => Deck(
  title: 'Native all-type roundtrip',
  projectPath: projectPath,
  slides: [for (final type in SlideType.values) _filled(type)],
);

Slide _filled(SlideType type) {
  final title = 'Native ${type.name}';
  var slide = slideMetInhoud(type).copyWith(
    title: title,
    notes: 'Notitie ${type.name}',
    cssClass: 'authored-${type.name.toLowerCase()}',
    anchor: 'native-${type.name.toLowerCase()}',
    showLogo: false,
    showFooter: false,
    advanceDuration: 3.5,
  );
  if (type.usesFreeMarkdownBody || type == SlideType.freeMarkdown) {
    slide = slide.copyWith(
      customMarkdown:
          '# $title\n\nVrije **tekst** met een eigen class.\n\n- Eerste\n- Tweede',
    );
  }
  if (type.usesFreeMarkdownBody || type == SlideType.freeMarkdown) {
    // The parser also exposes these list lines as derived editor metadata.
    slide = slide.copyWith(bullets: const ['Eerste', 'Tweede']);
  }
  if (type == SlideType.quote || type == SlideType.chart) {
    slide = slide.copyWith(title: '');
  }
  if (type == SlideType.canvas) {
    final body = slide.customMarkdown
        .replaceAllMapped(
          RegExp(r'(## [^\n]+)\n'),
          (m) => '${m[1]}\n\nNative inhoud.\n',
        )
        .trimRight();
    slide = slide.copyWith(
      customMarkdown: body,
      subtitle: RegExp(r'^## (.+)$', multiLine: true).allMatches(body).last[1],
    );
  }
  if (type == SlideType.finding) {
    slide = slide.copyWith(
      title: 'Native finding',
      customMarkdown: const FindingSpec(
        heading: 'Native finding',
        scopeObject: 'scope.example',
        description: 'Native beschrijving',
        confirmation: 'Gecontroleerd',
        impact: 'Meetbaar gevolg',
        recommendation: 'Native advies',
      ).toMarkdown().trimRight(),
    );
  }
  if (type == SlideType.chart) {
    slide = slide.copyWith(
      customMarkdown: ChartSpec(
        title: title,
        source: 'data/series.csv',
        x: const ['Een', 'Twee'],
        series: const [
          ChartSeries(name: 'Serie', data: [12, 34]),
        ],
      ).toBlock(),
    );
  }
  if (type == SlideType.code) {
    slide = slide.copyWith(customMarkdown: 'final waarde = 42;');
  }
  if (type == SlideType.bullets) {
    slide = slide.copyWith(audioPath: 'audio/tone.wav');
  }
  if (type == SlideType.video) {
    slide = slide.copyWith(
      videoCaptions: 'media/film.vtt',
      videoStartMs: 100,
      videoEndMs: 800,
    );
  }
  if (type == SlideType.image ||
      type == SlideType.twoImages ||
      type == SlideType.bulletsImage) {
    slide = slide.copyWith(
      imageCaption: 'Links | bijschrift',
      imageAltText: 'Afbeelding links',
      imageFocalX: 0.25,
      imageFocalY: 0.75,
    );
  }
  if (type == SlideType.twoImages) {
    slide = slide.copyWith(
      imageCaption2: 'Rechts',
      imageAltText2: 'Afbeelding rechts',
    );
  }
  if (type == SlideType.bulletsImage) slide = slide.copyWith(imageSize: 40);
  if (type == SlideType.image || type == SlideType.twoImages) {
    slide = slide.copyWith(
      imageSize: type == SlideType.image ? 0 : 50,
      marpStyle: slide.marpStyle.copyWith(
        imageFit: 'contain',
        imageFilters: const [],
      ),
    );
  }
  if (type.backedByTable) {
    final rows = _filledRows(slide);
    slide = slide.copyWith(
      tableRows: rows,
      tableColumnAlignments: [for (final _ in rows.first) TableAlign.left],
    );
  }
  return slide;
}

Object? _jsonValue(Object? value) {
  if (value is Enum) return value.name;
  if (value is ImageCallout) return value.toJson();
  if (value is List) return value.map(_jsonValue).toList();
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', _jsonValue(item)));
  }
  return value;
}

String assetDigest(
  String path,
  String? projectPath, {
  Map<String, List<int>> members = const {},
}) {
  final bytes = WebAssetStore.bytesFor(path) ?? members[path];
  if (bytes != null) return sha256.convert(bytes).toString();
  final resolved = resolveSlideAssetPath(path, projectPath);
  if (resolved == null) throw StateError('Asset does not resolve: $path');
  return sha256.convert(File(resolved).readAsBytesSync()).toString();
}

Map<String, Object?> nativeSlideSnapshot(
  Slide slide,
  String? projectPath, {
  Map<String, List<int>> members = const {},
}) => {
  for (final field in slideRoundtripCases.entries)
    field.key: switch (field.key) {
      'imagePath' ||
      'imagePath2' ||
      'audioPath' ||
      'videoPath' ||
      'videoCaptions' =>
        (field.value.read(slide) as String).isEmpty
            ? ''
            : assetDigest(
                field.value.read(slide) as String,
                projectPath,
                members: members,
              ),
      'galleryImages' =>
        slide.galleryImages
            .map(
              (line) => line.replaceAllMapped(
                RegExp(r'\]\(([^)]+)\)'),
                (m) =>
                    '](${assetDigest(m[1]!, projectPath, members: members)})',
              ),
            )
            .toList(),
      'customMarkdown' when slide.type == SlideType.chart => _chartSnapshot(
        slide,
        projectPath,
        members: members,
      ),
      _ => _jsonValue(field.value.read(slide)),
    },
};

Object _chartSnapshot(
  Slide slide,
  String? projectPath, {
  Map<String, List<int>> members = const {},
}) {
  final spec = ChartSpec.parse(slide.customMarkdown);
  return {
    'spec': spec.copyWith(clearSource: true).toBlock(),
    'source': spec.source == null
        ? null
        : assetDigest(spec.source!, projectPath, members: members),
  };
}

List<Map<String, Object?>> nativeDeckSnapshot(
  Deck deck, {
  Map<String, List<int>> members = const {},
}) => [
  for (final slide in deck.slides)
    nativeSlideSnapshot(slide, deck.projectPath, members: members),
];

List<List<String>> _filledRows(Slide slide) => switch (slide.type) {
  SlideType.table => [
    ['Onderdeel', 'Waarde'],
    ['Native rij', '42'],
  ],
  SlideType.assets => const AssetOverviewSpec(
    groups: [
      AssetGroup(name: 'Native groep', total: 42, atRisk: 2, newlyFound: 1),
    ],
  ).toTableRows(),
  SlideType.discoveries => const DiscoveriesSpec(
    discoveries: [
      Discovery(
        name: 'Native dienst',
        kind: 'Webapplicatie',
        daysUnnoticed: 3,
        owner: 'Testteam',
      ),
    ],
  ).toTableRows(),
  SlideType.checklist => const ChecklistSpec(
    rows: [
      ChecklistRow(id: 'T1', test: 'Native controle', note: 'Gecontroleerd'),
    ],
  ).toTableRows(),
  SlideType.scopeMatrix => const ScopeMatrixSpec(
    rows: [ScopeRow(object: 'scope.example', note: 'Native scope')],
  ).toTableRows(),
  SlideType.scorecard => const ScorecardSpec(
    entries: [
      ScorecardEntry(
        label: 'Native meting',
        value: 42,
        previous: 40,
        unit: '%',
      ),
    ],
  ).toTableRows(),
  SlideType.controlStatus => const ControlStatusSpec(
    rows: [
      ControlStatusRow(
        id: 'C1',
        control: 'Native maatregel',
        maturity: 2,
        owner: 'Testteam',
      ),
    ],
  ).toTableRows(),
  SlideType.findingsSummary => FindingsSummarySpec(
    counts: {FindingsSummarySpec.order.first: 2},
    resolved: 1,
  ).toTableRows(),
  SlideType.matrix => [
    slide.tableRows.first,
    [for (var i = 0; i < slide.tableRows.first.length; i++) 'Native $i'],
  ],
  SlideType.gantt => [
    slide.tableRows.first,
    ['Native taak', '2026-11-01', '2d', '25', ''],
  ],
  _ => throw StateError('Add a filled table fixture for ${slide.type.name}'),
};
