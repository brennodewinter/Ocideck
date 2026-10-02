import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../utils/form_block_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import 'markdown_editor_theme.dart';

/// Tekent een `x-embed-form-block` in de visuele editor als de gerenderde vorm
/// van zijn eigen bron (FORM_INTAKE.md §4.9).
///
/// Zonder deze builder — en de embed eronder — viel het hele document terug op
/// brontekst zodra er één formulier in stond: een `<!-- field … -->` is rauwe
/// HTML. Het blok is hier **alleen-lezen**: een formulier wordt ingevuld in de
/// invulweergave en geschreven in de auteursweergave; de gewone editor bewaart
/// het onaangetast. De weergave is dezelfde `DocumentMarkdownView` als die van de
/// lezer, zonder de markers: er is geen tweede renderpad.
///
/// Er staat bewust geen eigen tekst in ("Antwoord:", "Notice"): alles wat de
/// gebruiker ziet komt uit het document zelf, dus er is niets te vertalen en niets
/// dat uit de pas kan lopen met de taal van het formulier.
class FormBlockEmbedBuilder extends EmbedBuilder {
  const FormBlockEmbedBuilder();

  @override
  String get key => EmbeddableFormBlock.blockType;

  /// Een blok vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final profile = DocumentStyleScope.maybeOf(context);
    final data = embedContext.node.value.data as String? ?? '';
    final first = data.split('\n').first;

    Widget markdown(String text) => DocumentMarkdownView(
      text,
      maxTextWidth: null,
      themeProfile: profile,
      chartTheme: profile,
    );

    switch (formBlockKind(first)) {
      case FormBlockKind.header:
        return _Header(first);
      case FormBlockKind.notice:
        return _Panel(child: markdown(_innerOf(data)));
      case FormBlockKind.field:
        final parts = splitFieldBlock(data);
        return Semantics(
          label: _attr(first, 'id'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (parts.label.trim().isNotEmpty) markdown(parts.label),
              _Panel(
                minHeight: 40,
                child: parts.answer.trim().isEmpty
                    ? const SizedBox.shrink()
                    : markdown(parts.answer),
              ),
            ],
          ),
        );
      case null:
        return markdown(data);
    }
  }

  /// De regels tussen de eerste en de laatste (de twee markers van een notice).
  static String _innerOf(String data) {
    final lines = data.split('\n');
    if (lines.length < 3) return '';
    return lines.sublist(1, lines.length - 1).join('\n');
  }

  static String? _attr(String markerLine, String key) {
    final scan = scanMarkerLine(
      markerLine.endsWith('\r')
          ? markerLine.substring(0, markerLine.length - 1)
          : markerLine,
    );
    return scan is FoundMarker ? scan.attr(key) : null;
  }
}

/// Een kader dat het antwoord (of de notice) van de tekst eromheen scheidt.
/// Kleuren komen uit het actieve kleurenschema, nooit hardgecodeerd.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.minHeight = 0});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// De `form`-marker: alleen het formulier-id en de versie, zoals ze in de marker
/// staan — geen eigen woorden.
class _Header extends StatelessWidget {
  const _Header(this.markerLine);

  final String markerLine;

  @override
  Widget build(BuildContext context) {
    final id = FormBlockEmbedBuilder._attr(markerLine, 'id') ?? '';
    final version = FormBlockEmbedBuilder._attr(markerLine, 'version');
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        version == null ? id : '$id · v$version',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
