import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/table_of_contents.dart';
import '../../utils/toc_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import 'markdown_editor_theme.dart';

/// Tekent een `x-embed-toc`-blok in de visuele (Quill) editor als dezelfde
/// inhoudsopgave-voorbeeldweergave die de documentlezer toont.
///
/// Zonder deze builder — en de embed eronder — viel het hele document terug op
/// brontekst zodra iemand een inhoudsopgave invoegde: `<!-- toc -->` is HTML,
/// en rauwe HTML is een visuele-modus-beperking.
///
/// De koppen komen uit het Quill-document zelf, niet uit de embed: de marker
/// draagt geen inhoud, en de voorbeeldweergave moet meelopen met wat er nú in
/// het document staat.
class TocEmbedBuilder extends EmbedBuilder {
  const TocEmbedBuilder();

  @override
  String get key => EmbeddableToc.tocType;

  /// Een inhoudsopgave is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final profile = DocumentStyleScope.maybeOf(context);
    return DocumentMarkdownView(
      tocMarker,
      tocSource: _headingsMarkdown(embedContext.controller.document),
      maxTextWidth: null,
      themeProfile: profile,
      chartTheme: profile,
    );
  }

  /// De koppen van [document] als kale markdown-koprijen.
  ///
  /// Alleen de kopregels — niet het hele document opnieuw serialiseren: deze
  /// builder draait bij elke toetsaanslag in de editor, en de inhoudsopgave
  /// heeft aan de koppen genoeg.
  String _headingsMarkdown(Document document) {
    final buf = StringBuffer();
    for (final node in document.root.children) {
      if (node is! Line) continue;
      final level = node.style.attributes[Attribute.header.key]?.value;
      if (level is! int || level < 1) continue;
      final text = node.toPlainText().trim();
      if (text.isEmpty) continue;
      buf.writeln('${'#' * level} $text');
    }
    return buf.toString();
  }
}
