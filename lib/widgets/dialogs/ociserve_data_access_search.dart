part of 'ociserve_data_access.dart';

List<Object?> _recordsFor(Object? value) => switch (value) {
  List<Object?> list => list,
  Map<Object?, Object?> map => [map],
  _ => [value],
};

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
