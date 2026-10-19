import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/source_fragment_embed_syntax.dart';
import 'embedded_field_actions.dart';

/// Tekent een `x-embed-source-fragment` in de visuele editor: het stuk bron
/// dat de rijke-tekstlaag niet verliesvrij kan dragen (HTML-commentaar,
/// ontsnapte leestekens, een losse tabelregel — zie [sourceFragmentRanges]).
///
/// Vóór deze embed wierp één zo'n regel het hele document terug op de
/// Bron-modus: een `<!-- marp: ... -->` of `\*` in een kop en niets was meer
/// visueel te schrijven. Nu wordt alleen dát brok een atomair vlak — de tekst
/// ervoor en erna blijft gewone rijke tekst — en komt de bron byte-getrouw
/// weer uit de codec.
///
/// Het vlak is bewerkbaar (het voetnootdefinitie-patroon): wat je typt landt
/// via dezelfde uitgestelde terugschrijver weer in de embed, zodat één tik op
/// een losgekoppelde knoop de tekst nooit boven in het document plakt.
class SourceFragmentEmbedBuilder extends EmbedBuilder {
  const SourceFragmentEmbedBuilder();

  @override
  String get key => EmbeddableSourceFragment.fragmentType;

  /// Een fragment is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data as String? ?? '';
    final mono = _monoStyle(context);
    if (embedContext.readOnly) {
      return _SourceFragmentBox(child: Text(source, style: mono));
    }
    return _EditableSourceFragment(
      source: source,
      mono: mono,
      embedContext: embedContext,
    );
  }
}

TextStyle _monoStyle(BuildContext context) {
  final style = DefaultTextStyle.of(context).style;
  return style.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Courier New'],
    fontSize: (style.fontSize ?? 15) * 0.85,
    height: 1.4,
  );
}

/// De vaste vorm van een fragment: een subtiel afgezet vlak met het
/// bijschrift "Bron", zodat je ziet dat dít stuk bewust als brontekst reist —
/// niet als kapotte opmaak die je moet gaan fixen.
class _SourceFragmentBox extends StatelessWidget {
  const _SourceFragmentBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.d('Bron'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          child,
        ],
      ),
    );
  }
}

class _EditableSourceFragment extends StatefulWidget {
  const _EditableSourceFragment({
    required this.source,
    required this.mono,
    required this.embedContext,
  });

  final String source;
  final TextStyle mono;
  final EmbedContext embedContext;

  @override
  State<_EditableSourceFragment> createState() =>
      _EditableSourceFragmentState();
}

class _EditableSourceFragmentState extends State<_EditableSourceFragment> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.source,
  );
  final FocusNode _focus = FocusNode();

  /// De tekst die nog naar het document moet; `null` als er niets wacht.
  String? _pending;
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_write);
  }

  @override
  void didUpdateWidget(_EditableSourceFragment old) {
    super.didUpdateWidget(old);
    // Komt er van buiten een andere bron binnen (ongedaan maken), dan wint die
    // — maar niet terwijl je zelf typt.
    if (widget.source != _controller.text && !_focus.hasFocus) {
      _controller
        ..removeListener(_write)
        ..text = widget.source
        ..addListener(_write);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Plant het terugschrijven ná deze frame in plaats van er middenin.
  ///
  /// Dezelfde reden als bij de tabel- en voetnoot-embed: terugschrijven
  /// vervangt de embed-knoop, en twee schrijfacties in één frame laten de
  /// tweede op een losgekoppelde knoop landen — die heeft `documentOffset` 0,
  /// en dan plakt de bron bovenaan het document dwars door de tekst heen.
  void _write() {
    _pending = _controller.text;
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flush();
    });
  }

  void _flush() {
    final text = _pending;
    _pending = null;
    if (text == null || text == widget.source) return;
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableSourceFragment(text),
      null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SourceFragmentBox(
      // Zonder deze wikkel voert Quill de tekstbewerking van dit veld uit, met
      // de inhoud van het hele document — zie [EmbeddedFieldActions] (#1565).
      child: EmbeddedFieldActions(
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: widget.mono,
          maxLines: null,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
