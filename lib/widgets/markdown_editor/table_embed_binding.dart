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

  /// De eigenaarstoken die de store bij onze laatste [TableEmbedControllerStore.obtain]
  /// uitgaf. [dispose] geeft hem mee aan [TableEmbedControllerStore.release],
  /// zodat die weet of de entry inmiddels een andere eigenaar heeft.
  late Object _ownerToken;
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

  TableEditController _obtainController() {
    final acquired = _controllerStore.obtain(
      _documentOffset,
      tableSource,
      onChanged: _tableChanged,
      onCellFocused: () => _embedContext.controller.skipRequestKeyboard = true,
    );
    _ownerToken = acquired.token;
    return acquired.controller;
  }

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

  void dispose() =>
      _controllerStore.release(_documentOffset, editor, _ownerToken);
}

/// Bewaart tabelcontrollers buiten de vluchtige widgets die ze tekenen.
class TableEmbedControllerStore {
  final Map<
    Object,
    ({TableEditController controller, String gfm, Object token})
  >
  _entries = {};

  /// Neemt de entry op [tableKey] over en geeft een verse eigenaarstoken
  /// terug. [release] van een oudere eigenaar is daarna werkloos: diens token
  /// past niet meer op de entry.
  ({TableEditController controller, Object token}) obtain(
    Object tableKey,
    String gfm, {
    required void Function(List<List<String>>, List<TableAlign>) onChanged,
    required VoidCallback? onCellFocused,
  }) {
    final token = Object();
    final entry = _entries[tableKey];
    final current = entry?.controller;
    final encoded = current == null
        ? null
        : encodeMarkdownTable(current.rows, alignments: current.alignments);
    if (current != null && (entry!.gfm == gfm || encoded == gfm)) {
      current.reconnect(onChanged: onChanged, onCellFocused: onCellFocused);
      _entries[tableKey] = (controller: current, gfm: entry.gfm, token: token);
      return (controller: current, token: token);
    }
    if (current != null) {
      // De verdrongen controller kan deze frame nog aan cellen hangen die
      // pas aan het einde van de frame ontmanteld worden; opruimen na de
      // layout, niet middenin.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    final decoded = decodeMarkdownTableWithAlignment(gfm.split('\n'));
    final controller = TableEditController(
      rows: decoded.rows,
      alignments: decoded.alignments,
      onChanged: onChanged,
      onCellFocused: onCellFocused,
    );
    _entries[tableKey] = (controller: controller, gfm: gfm, token: token);
    return (controller: controller, token: token);
  }

  void remember(Object tableKey, TableEditController controller, String gfm) {
    _entries[tableKey] = (
      controller: controller,
      gfm: gfm,
      // Bewaar de lopende eigenaarstoken: een verse zou een al geplande
      // [release] van díé binding alsnog doen doorwerken.
      token: _entries[tableKey]?.token ?? Object(),
    );
  }

  /// Verwijdert een controller pas na de huidige frame, en alleen als de
  /// entry dan nog toebehoort aan degene die [token] meegaf.
  ///
  /// Een Quill-update ruimt de oude embedwidget op en bouwt haar meteen weer
  /// op; [obtain] adopteert de entry dan onder een nieuwe token en deze
  /// vrijgave doet niets meer. Datzelfde geldt wanneer de embed van
  /// widgettype wisselt (tabel ↔ tijdlijn): de opvolger obtaint vóórdat de
  /// voorganger ontmanteld is — diens [release] zou zonder de token de net
  /// geadopteerde controller opruimen en de levende cellen met gedode
  /// focusnodes achterlaten.
  void release(Object tableKey, TableEditController controller, Object token) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final entry = _entries[tableKey];
      if (entry == null ||
          entry.controller != controller ||
          entry.token != token) {
        return;
      }
      _entries.remove(tableKey);
      controller.dispose();
    });
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.controller.dispose();
    }
    _entries.clear();
  }
}
