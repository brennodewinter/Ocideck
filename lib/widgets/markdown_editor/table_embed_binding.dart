import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/slide.dart' show TableAlign;
import '../../services/markdown_table_codec.dart';
import '../reader/table_edit_controller.dart';

typedef TableSourceTransform = String Function(String source);
typedef TableEmbedFactory = BlockEmbed Function(String source);

/// Verbindt één bewerkbare GFM-tabel met haar atomaire Quill-embed.
///
/// Quill vervangt de embedknoop bij iedere inhoudswijziging. De tabelcellen
/// mogen daarbij niet worden vervangen: dan verdwijnen focus, selectie en de
/// eigen tekstverbinding van de cel. Deze binding bewaart daarom de stabiele
/// positie, coalescet schrijfacties tot één per frame en laat de celcontroller
/// buiten de vluchtige embedwidget leven.
class TableEmbedBinding {
  factory TableEmbedBinding({
    required TableEmbedControllerStore controllerStore,
    required EmbedContext embedContext,
    required String source,
    required TableSourceTransform unwrapSource,
    required TableSourceTransform wrapTable,
    required TableEmbedFactory makeEmbed,
    required bool Function() isMounted,
  }) => TableEmbedBinding._(
    controllerStore,
    embedContext,
    source,
    unwrapSource,
    wrapTable,
    makeEmbed,
    isMounted,
  );

  TableEmbedBinding._(
    this._controllerStore,
    this._embedContext,
    this._source,
    this._unwrapSource,
    this._wrapTable,
    this._makeEmbed,
    this._isMounted,
  ) : _documentOffset = _embedContext.node.documentOffset {
    editor = _obtainController();
  }

  final TableEmbedControllerStore _controllerStore;
  EmbedContext _embedContext;
  final TableSourceTransform _unwrapSource;
  final TableSourceTransform _wrapTable;
  final TableEmbedFactory _makeEmbed;
  final bool Function() _isMounted;

  late TableEditController editor;
  int _documentOffset;
  String _source;
  String? _pending;
  bool _flushScheduled = false;

  String get currentSource => _pending ?? _source;
  String get tableSource => _unwrapSource(currentSource);

  void reconnect(EmbedContext embedContext, String source) {
    _embedContext = embedContext;
    final node = embedContext.node;
    if (node.parent != null) _documentOffset = node.documentOffset;
    _source = source;
    editor = _obtainController();
  }

  TableEditController _obtainController() => _controllerStore.obtain(
    _documentOffset,
    tableSource,
    onChanged: _tableChanged,
    onCellFocused: () => _embedContext.controller.skipRequestKeyboard = true,
  );

  void _tableChanged(List<List<String>> rows, List<TableAlign> alignments) {
    _pending = _wrapTable(encodeMarkdownTable(rows, alignments: alignments));
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (_isMounted()) _flush();
    });
  }

  void _flush() {
    final source = _pending;
    _pending = null;
    if (source == null) return;
    replaceSource(source, preserveEditor: true);
  }

  void clearPending() => _pending = null;

  void replaceTable(
    String gfm, {
    bool discrete = false,
    VoidCallback? onDiscreteEdit,
  }) => replaceSource(
    _wrapTable(gfm),
    discrete: discrete,
    onDiscreteEdit: onDiscreteEdit,
  );

  void replaceSource(
    String source, {
    bool discrete = false,
    bool preserveEditor = false,
    VoidCallback? onDiscreteEdit,
    BlockEmbed? embed,
  }) {
    if (source == _source) return;
    if (discrete) onDiscreteEdit?.call();
    if (preserveEditor) {
      _controllerStore.remember(_documentOffset, editor, _unwrapSource(source));
    }
    _source = source;
    _embedContext.controller.replaceText(
      // Een embed heeft lengte 1. De positie blijft geldig nadat Quill de oude
      // knoop loskoppelt; diens documentOffset zelf valt dan juist terug op 0.
      _documentOffset,
      1,
      embed ?? _makeEmbed(source),
      _embedContext.controller.selection,
      // De cel bezit haar eigen tekstverbinding. Quill mag die bij de
      // vervanging niet terugpakken of naar het blokbegin scrollen.
      ignoreFocus: true,
    );
  }

  void dispose() => _controllerStore.release(_documentOffset, editor);
}

/// Bewaart tabelcontrollers buiten de vluchtige widgets die ze tekenen.
class TableEmbedControllerStore {
  final Map<Object, ({TableEditController controller, String gfm})> _entries =
      {};
  final Map<Object, Object> _releaseTokens = {};

  TableEditController obtain(
    Object tableKey,
    String gfm, {
    required void Function(List<List<String>>, List<TableAlign>) onChanged,
    required VoidCallback? onCellFocused,
  }) {
    _releaseTokens.remove(tableKey);
    final entry = _entries[tableKey];
    final current = entry?.controller;
    final encoded = current == null
        ? null
        : encodeMarkdownTable(current.rows, alignments: current.alignments);
    if (current != null && (entry!.gfm == gfm || encoded == gfm)) {
      current.reconnect(onChanged: onChanged, onCellFocused: onCellFocused);
      return current;
    }
    current?.dispose();
    final decoded = decodeMarkdownTableWithAlignment(gfm.split('\n'));
    final controller = TableEditController(
      rows: decoded.rows,
      alignments: decoded.alignments,
      onChanged: onChanged,
      onCellFocused: onCellFocused,
    );
    _entries[tableKey] = (controller: controller, gfm: gfm);
    return controller;
  }

  void remember(Object tableKey, TableEditController controller, String gfm) {
    _entries[tableKey] = (controller: controller, gfm: gfm);
  }

  /// Verwijdert een controller pas na de huidige frame.
  ///
  /// Een Quill-update ruimt de oude embedwidget op en bouwt haar meteen weer
  /// op. [obtain] annuleert deze vrijgave dan; bij een werkelijk verwijderde
  /// tabel blijft er niemand over en wordt de entry wel opgeruimd.
  void release(Object tableKey, TableEditController controller) {
    final token = Object();
    _releaseTokens[tableKey] = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_releaseTokens[tableKey] != token) return;
      _releaseTokens.remove(tableKey);
      final entry = _entries[tableKey];
      if (entry?.controller != controller) return;
      _entries.remove(tableKey);
      controller.dispose();
    });
  }

  void dispose() {
    _releaseTokens.clear();
    for (final entry in _entries.values) {
      entry.controller.dispose();
    }
    _entries.clear();
  }
}
