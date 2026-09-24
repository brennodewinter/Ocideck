part of 'ociserve_data_access.dart';

class _IndexedRecord {
  const _IndexedRecord(this.sourceIndex, this.value);

  final int sourceIndex;
  final Object? value;
}

List<_IndexedRecord> _recordsFor(Object? value) => switch (value) {
  List<Object?> list => [
    for (var index = 0; index < list.length; index++)
      _IndexedRecord(index, list[index]),
  ],
  Map<Object?, Object?> map => [_IndexedRecord(0, map)],
  _ => [_IndexedRecord(0, value)],
};

String _jsonPointerSegment(Object? value) =>
    '$value'.replaceAll('~', '~0').replaceAll('/', '~1');

String _searchText(BuildContext context, Object? value) {
  final parts = <String>[];
  void collect(Object? item, [String sourceKey = '']) {
    switch (item) {
      case Map():
        for (final entry in Map<Object?, Object?>.from(item).entries) {
          final key = '${entry.key}';
          parts.add(key);
          parts.add(_fieldLabel(context, key));
          collect(entry.value, key);
        }
      case List():
        for (final child in item) {
          collect(child, sourceKey);
        }
      default:
        parts.add('$item');
        parts.add(_display(context, sourceKey, item));
    }
  }

  collect(value);
  return parts.join(' ').toLowerCase();
}
