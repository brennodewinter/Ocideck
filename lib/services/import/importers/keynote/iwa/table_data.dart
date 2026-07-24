import 'dart:convert';

import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'proto_wire.dart';

/// Shared string / error / rich-text lookups for a `TST.DataStore`.
///
/// `DataStore` keeps references to `TableDataList` objects for plaintext,
/// formula errors and rich-text payloads. This helper resolves those lists
/// once and exposes a simple `valueAt(index)` API used by [TableCellReader].
class TableData {
  TableData({
    this.strings = const {},
    this.richTexts = const {},
    this.errors = const {},
  });

  final Map<int, String> strings;
  final Map<int, String> richTexts;
  final Map<int, String> errors;

  /// Build the three lookup tables from the `DataStore` submessage inside
  /// [tableModel]. References inside the `DataStore` submessage use
  /// [tableModel]'s `objectReferences` list.
  static TableData read(IwaDocument doc, IwaObject tableModel) {
    final dataStore = tableModel.message.message(4);
    if (dataStore == null) return TableData();

    return TableData(
      strings: _readPlainStrings(doc, tableModel, dataStore, 4),
      richTexts: _readRichTexts(doc, tableModel, dataStore, 17),
      errors: _readPlainStrings(doc, tableModel, dataStore, 12),
    );
  }

  static Map<int, String> _readPlainStrings(
    IwaDocument doc,
    IwaObject tableModel,
    ProtoMessage dataStore,
    int field,
  ) {
    final idx = dataStore.varint(field);
    if (idx == null) return const {};
    final list = doc.resolveReference(tableModel, idx);
    if (list == null) return const {};

    final out = <int, String>{};
    for (final entry in list.message.messages(3)) {
      final key = entry.varint(1);
      final value = entry.string(3);
      if (key != null && value != null) out[key] = value;
    }
    return out;
  }

  static Map<int, String> _readRichTexts(
    IwaDocument doc,
    IwaObject tableModel,
    ProtoMessage dataStore,
    int field,
  ) {
    final idx = dataStore.varint(field);
    if (idx == null) return const {};
    final list = doc.resolveReference(tableModel, idx);
    if (list == null) return const {};

    final out = <int, String>{};
    for (final entry in list.message.messages(3)) {
      final key = entry.varint(1);
      final refIdx = entry.varint(4);
      if (key == null || refIdx == null) continue;

      final payload = doc.resolveReference(list, refIdx);
      final storageRef = payload?.message.varint(1);
      if (storageRef == null) continue;
      final storage = doc.resolveReference(payload!, storageRef);
      final text = storage == null ? null : _storageText(storage);
      if (text != null) out[key] = text;
    }
    return out;
  }

  static String? _storageText(IwaObject storage) {
    final chunks = <String>[];
    for (final b in storage.message.bytesList(3)) {
      try {
        var s = utf8.decode(b);
        try {
          s = Uri.decodeComponent(s);
        } on FormatException {
          // Not percent-encoded; use the UTF-8 string as-is.
        }
        chunks.add(s);
      } on FormatException {
        // Skip non-UTF-8 fragments.
      }
    }
    return chunks.isEmpty ? null : chunks.join();
  }
}
