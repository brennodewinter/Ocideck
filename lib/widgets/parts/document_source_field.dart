// Part of the document-editor library — see ../document_editor_screen.dart.
//
// Het bron-schrijfvlak met een niet-bewerkbare regelnummerkolom. Losgeknipt
// van de layouts-part zodat de kolom zijn eigen scroll- en telstaat mag
// houden zonder het bewerkscherm of de layouts verder op te rekken.
part of '../document_editor_screen.dart';

/// Lettermaat van de Bron-editor. De nummers gebruiken dezelfde regelhoogte,
/// anders lopen ze binnen een paar regels uit de pas met de tekst.
const double _kDocumentSourceFontSize = 14;

/// Regelafstand als factor van de lettermaat — zelfde waarde als `TextStyle.height`.
const double _kDocumentSourceLineHeightFactor = 1.5;

/// Pixelhoogte per logische regel. Soft-wrap telt hier bewust niet mee: een
/// regelnummer hoort bij een `\n` in het bestand, niet bij een omgebroken
/// weergave. Dat is hetzelfde contract als de markdown-editor van een deck.
const double _kDocumentSourceLineHeight =
    _kDocumentSourceFontSize * _kDocumentSourceLineHeightFactor;

/// Binnenmarge van het tekstveld. De kolom schuift met dezelfde top mee,
/// anders staan de nummers een regel te hoog of te laag.
const double _kDocumentSourceTopPadding = 16;

/// Telt de logische regels in de bron: elke `\n` opent een nieuwe regel, en
/// een leeg bestand is regel 1 — zoals een teksteditor dat doet.
int documentSourceLineCount(String text) => '\n'.allMatches(text).length + 1;

/// Breedte van de nummerkolom: genoeg cijfers plus ademruimte, zodat 999
/// niet tegen de tekst aandrukt en 9 niet in een te brede kolom zweeft.
double documentSourceGutterWidth(int lineCount) {
  final digits = lineCount.toString().length;
  return math.max(36, 12 + digits * 8);
}

/// Het bronveld: links nummers (niet in de selectie, niet in de bytes),
/// rechts de echte Markdown. De kolom ligt over de linkermarge van het
/// tekstveld, zodat een muiswiel daar dezelfde scroll beweegt.
class _DocumentSourceField extends StatefulWidget {
  final ThemeData theme;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<bool> Function() onSmartPaste;

  const _DocumentSourceField({
    required this.theme,
    required this.controller,
    required this.focusNode,
    required this.onSmartPaste,
  });

  @override
  State<_DocumentSourceField> createState() => _DocumentSourceFieldState();
}

class _DocumentSourceFieldState extends State<_DocumentSourceField> {
  late final ScrollController _scroll;
  late int _lineCount;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _lineCount = documentSourceLineCount(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(_DocumentSourceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _lineCount = documentSourceLineCount(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _scroll.dispose();
    super.dispose();
  }

  void _onText() {
    final next = documentSourceLineCount(widget.controller.text);
    if (next == _lineCount || !mounted) return;
    setState(() => _lineCount = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final lineCount = _lineCount;
    final gutterWidth = documentSourceGutterWidth(lineCount);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _DocSmartPasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _DocSmartPasteIntent(),
      },
      child: Actions(
        actions: {
          _DocSmartPasteIntent: CallbackAction<_DocSmartPasteIntent>(
            onInvoke: (_) {
              unawaited(widget.onSmartPaste());
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              scrollController: _scroll,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: theme.colorScheme.primary,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
                fontSize: _kDocumentSourceFontSize,
                height: _kDocumentSourceLineHeightFactor,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(
                  gutterWidth + 8,
                  _kDocumentSourceTopPadding,
                  16,
                  16,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: gutterWidth,
              child: IgnorePointer(
                child: _DocumentSourceGutter(
                  scroll: _scroll,
                  lineCount: lineCount,
                  width: gutterWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// De nummerkolom zelf. `IgnorePointer` in de ouder houdt de bytes buiten
/// bereik: je kunt de cijfers niet selecteren of overschrijven. De
/// schermlezer slaat ze over — de cursorpositie in het tekstveld is de
/// echte plaatsaanduiding; een muur van "1, 2, 3" zou die juist verstoren.
class _DocumentSourceGutter extends StatelessWidget {
  final ScrollController scroll;
  final int lineCount;
  final double width;

  const _DocumentSourceGutter({
    required this.scroll,
    required this.lineCount,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ColoredBox(
        color: AppTheme.slate100,
        key: const Key('document-source-gutter'),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: scroll,
            builder: (context, child) {
              final offset = scroll.hasClients ? scroll.offset : 0.0;
              return Transform.translate(
                offset: Offset(0, _kDocumentSourceTopPadding - offset),
                child: child,
              );
            },
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxWidth: width,
              minWidth: width,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < lineCount; index++)
                    SizedBox(
                      key: Key('document-source-line-${index + 1}'),
                      height: _kDocumentSourceLineHeight,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: _kDocumentSourceLineHeightFactor,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
