import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../utils/mermaid_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import 'markdown_editor_theme.dart';

/// Tekent een `x-embed-mermaid`-blok in de visuele editor als het gerenderde
/// diagram, in plaats van als monospace brontekst.
///
/// `DOCUMENT_MODE.md` §4.3 belooft mermaid als gerenderde kaart in de visuele
/// modus; lezer, voorvertoning, Pagina's, PDF en HTML-export deden dat al, de
/// editor als enige niet (#1920).
///
/// De weergave is bewust dezelfde [DocumentMarkdownView] die de lezer gebruikt,
/// en geen eigen kaart — dezelfde afweging als bij de pentest-envelop: er is
/// geen tweede renderpad, dus wat de auteur in de editor ziet is wat het
/// document toont, inclusief het terugvallen op een codeblok wanneer er geen
/// WebView is om mee te tekenen. De kaart is alleen-lezen; bewerken gaat via de
/// Bron-modus, net als bij de andere atomaire blokken.
class MermaidEmbedBuilder extends EmbedBuilder {
  const MermaidEmbedBuilder();

  @override
  String get key => EmbeddableMermaid.mermaidType;

  /// Een diagram is een blok, geen inline-teken: het vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final profile = DocumentStyleScope.maybeOf(context);
    final data = embedContext.node.value.data as String? ?? '';
    return DocumentMarkdownView(
      data,
      maxTextWidth: null,
      themeProfile: profile,
      chartTheme: profile,
    );
  }
}
