import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/slide.dart';
import '../../utils/chart_embed_syntax.dart';
import '../editors/chart_editor.dart';
import '../editors/embed_editor_dialog.dart';
import '../reader/document_markdown_view.dart';
import 'markdown_editor_theme.dart';

/// Tekent een `x-embed-chart`-blok in de visuele editor als de gerenderde
/// grafiek, in plaats van als monospace brontekst (#2751).
///
/// De weergave is bewust dezelfde [DocumentMarkdownView] die de lezer
/// gebruikt — één renderpad, dus wat de auteur ziet is wat het document
/// toont, inclusief de terugval op een codeblok als de fence alleen een
/// `source:`-verwijzing draagt of de parse mislukt.
///
/// Dubbelklik opent de bestaande [ChartEditor] en schrijft de bewerkte
/// fence terug op dezelfde knoop — de markdown zélf wordt nooit omgezet,
/// de fence blijft de drager (dezelfde weg als de tabel- en
/// bronfragment-embeds, met `documentOffset` ter bescherming tegen een
/// losgekoppelde knoop).
class ChartEmbedBuilder extends EmbedBuilder {
  const ChartEmbedBuilder();

  @override
  String get key => EmbeddableChart.chartType;

  /// Een grafiek is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final profile = DocumentStyleScope.maybeOf(context);
    final data = embedContext.node.value.data as String? ?? '';
    return GestureDetector(
      onDoubleTap: embedContext.readOnly
          ? null
          : () => _editChart(context, embedContext, data),
      child: DocumentMarkdownView(
        data,
        maxTextWidth: null,
        themeProfile: profile,
        chartTheme: profile,
      ),
    );
  }

  /// De bestaande grafiekeditor, op een wegwerp-[Slide] zoals de
  /// documentroute ([_editDocumentChart]) die al gebruikt. 'Toepassen'
  /// schrijft de fence verbatim terug op zijn eigen knoop.
  Future<void> _editChart(
    BuildContext context,
    EmbedContext embedContext,
    String block,
  ) async {
    var edited = block;
    final slide = Slide.create(SlideType.chart).copyWith(customMarkdown: block);
    final apply = await showEmbedEditorDialog(
      context,
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => edited = s.customMarkdown,
      ),
    );
    if (apply != true || !context.mounted || edited == block) return;
    final node = embedContext.node;
    if (node.parent == null) return;
    embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableChart(edited),
      null,
    );
  }
}
