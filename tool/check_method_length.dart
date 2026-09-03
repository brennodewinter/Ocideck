// Guards against method/function-length creep — the per-method sibling of the
// file-size ratchet in check_conventions.dart.
//
// A method, top-level function or constructor body may not exceed
// [maxMethodLines] lines (signature through closing brace, excluding the doc
// comment), EXCEPT the baselined declarations below whose ceiling is their
// length when the ratchet was introduced. A ceiling may SHRINK (split the
// method, then lower the number — the run prints a tip) but never grow, so long
// methods trend smaller instead of creeping bigger.
//
// Measurement is AST-based (the `analyzer` package) rather than a brace
// heuristic, so closures, multi-line signatures and `=>` bodies are counted
// correctly. Keys are `path::Enclosing.name` (stable across line edits).
//
// Exits non-zero (with the offending locations) when a rule is violated.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// A non-baselined declaration may not exceed this many lines — split it first.
const int maxMethodLines = 150;

/// Declarations already above [maxMethodLines] when the ratchet was introduced.
/// Each value is that declaration's ceiling: it may SHRINK (split it, then
/// lower the number) but never grow. Add a new entry only with a deliberate
/// reason; the goal is fewer and smaller entries over time.
const Map<String, int> methodLengthBaseline = {
  // +8 (#1881): showRail-guard die de rail laat invallen op smal web.
  // De methode stond al op de limiet.
  // +1 (#1963): onJumpToFindings-callback in _DeckStatusBar-aanroep.
  'lib/widgets/app_shell_main_layout.dart::_MainLayoutState.build': 159,
  // +12 (#1879): de "paneelvullend"-checkbox voor bulletsImage. De methode
  // stond al op de limiet.
  'lib/widgets/editors/bullets_image_editor.dart::_BulletsImageEditorState.build':
      162,
  // +13 (#1655, #1654): voetnoot-clip met ConstrainedBox + RepaintBoundary
  // in het documentvenster. De methode stond al op de limiet.
  'lib/widgets/reader/paged_document_view.dart::_PagedDocumentViewState._sheet':
      163,
  // +6 (#1605): herkenning van een afbeelding op eigen regel in de paragraaf-
  // tak. De methode stond al op de limiet; de afbeeldingsherkenning zelf staat
  // in de top-level _parseImageLine-helper.
  // +11 (#1647): Setext-kopherkenning in de paragraaf-fallback — de
  // _isSetextUnderline-helper staat buiten de methode.
  'lib/widgets/reader/document_markdown_view.dart::DocumentMarkdownView._parse':
      165,
  // +3 (#1405): missing-file check voor rechter kolomafbeelding in titel-
  // kolommodus. De methode stond al op de limiet.
  'lib/services/slide_quality_analyzer.dart::SlideQualityAnalyzer._checkMissingMedia':
      153,
  // +128 (#1405): layoutkeuze + beeldkolommen + kolombreedte in de titel-editor.
  'lib/widgets/editors/title_editor.dart::_TitleEditorState.build': 278,
  // -113 (#1859): build is opgeknipt in helpers _buildSlideSettings,
  // _buildBulletList en _buildWorkSurface; de vorige 154-regels versie is
  // teruggebracht tot 41 regels.
  'lib/widgets/editors/callout_editor.dart::_CalloutEditorDialogState.build':
      41,
  // +1 (#1931): themeLogoDarkMissing case in formatSlideQualityIssue.
  'lib/l10n/slide_quality_localization.dart::formatSlideQualityIssue': 151,
  // +3 (#1931): logoDarkRel in _buildPackageArchive.
  'lib/services/file/file_service_package.dart::FileServicePackage._buildPackageArchive':
      153,
  // +1 (#1931): donkere logo-import in importStyleProfileBytes.
  'lib/services/file/file_service_style_profile.dart::FileServiceStyleProfile.importStyleProfileBytes':
      151,
  // +12 (#1931): donkere-logo-UI in _slideLogoChildren.
  'lib/widgets/dialogs/parts/settings_dialog_colors.dart::_SettingsColors._slideLogoChildren':
      162,
  // Procesverbetering VSM/swimlane scene builder — extract lane packing next.
  'lib/services/improvement/flow_layout.dart::buildFlowScene': 163,
  // Procesverbetering block directives (matrix/canvas/tree/flow/phaseGate).
  // +8 (#1162): de twee navigatie-takken (`ocideck_slide_anchor`/`ocideck_next`),
  // al gehalveerd via de top-level `_firstDirective`-helper.
  'lib/services/markdown_parse/markdown_service_parse_directives.dart::_MarkdownParseDirectives._parseBlockDirectives':
      197,
  // +2 (#1162): `anchor`/`nextAnchor` doorgeven aan de Slide-constructor.
  // +15: tableDecoded/tableAlignments voor GFM-scheidingsrij-uitlijning.
  // +3: tableNumberColumns doorgeven aan Slide.
  // +19 (#1405): titel-kolommodus afleiding uit sawBgLeft/sawBgRight.
  // +4 (#1407): imageTitleAbove-afleiding + class-token-stripping + constructor-doorvoer.
  // +1: imageZoom-doorvoer in Slide-constructor.
  // +4 (#1162): menuLayout uit de klassetokens lezen, plus het filteren van de
  // menu-optietokens uit `effectiveClass`. Pure doorvoer van een nieuw veld.
  // Verlaagd van 208 naar 202: de rij losse tokenvergelijkingen in
  // `effectiveClass` werd één aanroep van `isOcideckWrittenClassToken`.
  'lib/services/markdown_service_parse.dart::_MarkdownParse._parseBlock': 202,
  // Procesverbetering SVG export for statistical chart types.
  'lib/services/marp_html/marp_html_service_charts.dart::_improvementChartSvg':
      203,
  // Procesverbetering engine thumbnails in the add-slide picker.
  // +2 (#1162): de `menu`-case (de wireframe zelf zit in `_paintMenuWireframe`).
  'lib/widgets/dialogs/add_slide_dialog.dart::SlideTypePreviewPainter.paint':
      130,
  // Procesverbetering preview switch for matrix/canvas/tree/flow/phaseGate.
  // Verlaagd van 165: improvement-cases naar improvement_dispatch.dart.
  // +3 (#1164): splitRunPosition-doorgifte in de drie bullet-cases (bullets,
  // twoBullets, bulletsImage) van de dispatch-switch; pure plumbing van een
  // nieuw veld, geen gedrag om uit te tillen.
  // +8 (#1162): de `menu`-case (de _MenuPreview-aanroep). Pure dispatch: één case
  // valt niet zinvol uit een type→widget-switch te tillen. +1: de
  // onMenuBlockTap-doorgifte voor de klik-om-te-springen. +2: de categorie en
  // zijn terugroep, voor het wisselen tussen groepen blokken.
  // +1 (#1828): calloutRevealedBulletCount doorgeven aan _BulletsImagePreview.
  'lib/widgets/slides/slide_preview.dart::SlidePreviewWidget._buildContent':
      161,
  // +2 (#1238): ganttScale/ganttSections in copyWith — pure plumbing.
  // +3: tableColumnAlignments-parameter voor GFM-uitlijning.
  // +2: tableNumberColumns-parameter.
  // +4 (#1405): titleColumnLayout/titleColumnWidth in copyWith.
  // +2 (#1407): imageTitleAbove-parameter + doorvoer in copyWith.
  // +2: imageZoom-parameter + doorvoer in copyWith.
  // +2 (#1162): menuLayout-parameter + doorvoer in copyWith.
  // +6 (#1824): callouts, calloutPresentation, calloutReveal-parameters +
  // doorvoer in copyWith voor image callouts.
  'lib/models/slide.dart::Slide.copyWith': 172,
  // +2 (#1238): gantt scale/sections instellingen — twee _SettingRow's.
  // Verlaagd van 188 naar 186, en daarna naar 183: de methode meet 183.
  'lib/widgets/panels/editor_panel_slide_settings.dart::_SlideSettingsBody._groups':
      183,
  // +2: reportLanguage-parameter + getalnotatie in cell().
  'lib/widgets/slides/previews/table_preview.dart::_TablePreview.build': 152,
  // +8: tabel-split actie bij tableDensityMinimum-warning.
  'lib/widgets/panels/slide_quality_actions.dart::buildSlideQualityActions':
      158,
  // +1 (#1769): de ODP-case in de formaat-switch. De methode stond al op de
  // limiet; één case extra is onherleidbare plumbing.
  'lib/services/export_service.dart::ExportService.export': 125,
  // +12 (#1807): zeven nieuwe SlideField-cases (anchor, nextAnchor, ganttScale,
  // ganttSections, menuLayout, tableColumnAlignments, tableNumberColumns) in
  // een exhaustive switch — onherleidbare plumbing, één case per veld.
  // +30 (#1808): tien extra SlideField-cases (timelineLayout, timelineReveal,
  // timelineAnimationMs, bulletMarkerOverride, improvementLayout, privacy,
  // quality, findingRole, aiAssistedFields, viewLimit). Zelfde vorm: exhaustive
  // switch, één case per veld, niet uit te tillen.
  // +9 (#1824): callouts, calloutPresentation, calloutReveal — drie nieuwe
  // cases in de exhaustive switch, zelfde vorm, niet uit te tillen.
  'lib/collab/deck_op.dart::_slideWithField': 201,
};

bool _isTranslationData(String path) =>
    path.replaceAll(r'\', '/').contains('lib/l10n/translations/');

void main() {
  final measured = <String, ({int length, String location})>{};

  for (final file in _dartFiles(Directory('lib'))) {
    final path = file.path.replaceAll(r'\', '/');
    if (_isTranslationData(path)) continue;

    final result = parseFile(
      path: file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final visitor = _DeclVisitor(path, result.lineInfo);
    result.unit.visitChildren(visitor);
    measured.addAll(visitor.found);
  }

  final oversize = <String>[];
  final shrunk = <String>[];

  measured.forEach((key, m) {
    final ceiling = methodLengthBaseline[key];
    if (ceiling != null) {
      if (m.length > ceiling) {
        oversize.add(
          '${m.location}: $key is ${m.length} lines (ceiling $ceiling)',
        );
      } else if (m.length < ceiling) {
        shrunk.add('$key: ${m.length} (ceiling $ceiling)');
      }
    } else if (m.length > maxMethodLines) {
      oversize.add(
        '${m.location}: $key is ${m.length} lines (max $maxMethodLines)',
      );
    }
  });

  if (oversize.isEmpty) {
    stdout.writeln(
      'Method length OK: every declaration within its ceiling '
      '(max $maxMethodLines, ${methodLengthBaseline.length} baselined).',
    );
    if (shrunk.isNotEmpty) {
      shrunk.sort();
      stdout.writeln(
        'Tip: ${shrunk.length} baselined declaration(s) shrank — lower their '
        'methodLengthBaseline to lock in the win:\n    ${shrunk.join('\n    ')}',
      );
    }
    exit(0);
  }

  oversize.sort();
  stderr.writeln('Method length check FAILED:');
  stderr.writeln(
    '  ${oversize.length} declaration(s) over the limit — split into helpers, '
    'or (deliberately) add/raise an entry in methodLengthBaseline '
    '(tool/check_method_length.dart):\n    ${oversize.join('\n    ')}',
  );
  exit(1);
}

/// Collects named, body-bearing declarations at the top level of the unit or a
/// type. Local functions are skipped — they count toward their enclosing
/// declaration, which is measured as a whole.
class _DeclVisitor extends RecursiveAstVisitor<void> {
  _DeclVisitor(this.path, this.lineInfo);

  final String path;
  final LineInfo lineInfo;
  final found = <String, ({int length, String location})>{};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _record(node, node.body, _enclosing(node), node.name.lexeme);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name?.lexeme;
    final label = name == null ? '<new>' : 'new.$name';
    _record(node, node.body, _enclosing(node), label);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Only top-level functions; locals (parent is a statement) are part of the
    // method that holds them.
    if (node.parent is CompilationUnit) {
      _record(node, node.functionExpression.body, '', node.name.lexeme);
    }
    super.visitFunctionDeclaration(node);
  }

  /// Nearest enclosing type name (class/extension/mixin/enum), or '' for a
  /// top-level declaration.
  String _enclosing(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      // analyzer 12 exposes the name of class/enum declarations through
      // `namePart` (augmentation-aware); mixin/extension still use `name`.
      if (p is ClassDeclaration) return p.namePart.typeName.lexeme;
      if (p is EnumDeclaration) return p.namePart.typeName.lexeme;
      if (p is MixinDeclaration) return p.name.lexeme;
      if (p is ExtensionDeclaration) return p.name?.lexeme ?? '<extension>';
    }
    return '';
  }

  void _record(AstNode node, FunctionBody body, String enclosing, String name) {
    // Abstract/external declarations have no body to measure.
    if (body is EmptyFunctionBody) return;
    // Measure from the declaration itself (after its doc comment/metadata)
    // through the end of the body.
    final start = node is AnnotatedNode
        ? node.firstTokenAfterCommentAndMetadata.offset
        : node.offset;
    final startLine = lineInfo.getLocation(start).lineNumber;
    final endLine = lineInfo.getLocation(node.end).lineNumber;
    final length = endLine - startLine + 1;
    final qualified = enclosing.isEmpty ? name : '$enclosing.$name';
    found['$path::$qualified'] = (length: length, location: '$path:$startLine');
  }
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
