/// RFC 6901-escaping houdt sleutels met `~` en `/` herkenbaar in een pointer.
String jsonPointerFromSegments(Iterable<Object?> segments) =>
    ['', ...segments.map(_escapeJsonPointerSegment)].join('/');

String appendJsonPointerSegment(String pointer, Object? segment) =>
    [pointer, _escapeJsonPointerSegment(segment)].join('/');

String _escapeJsonPointerSegment(Object? segment) =>
    '$segment'.replaceAll('~', '~0').replaceAll('/', '~1');
