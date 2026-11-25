import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/log.dart';

/// Berichten naar het publieksvenster. De enumnamen zijn de namen op de draad.
enum AudienceMethod {
  // Oude snapshots bevatten alleen de dia-index en de gegevens die afweken.
  update(
    {'index': _Field.integer},
    {
      'seq': _Field.integer,
      'blank': _Field.integer,
      'richTextPage': _Field.integer,
      'stepIndex': _Field.integer,
      'menuCategory': _Field.integer,
      'timedPhase': _Field.integer,
      'countdown': _Field.integer,
      'timelineView': _Field.number,
    },
  ),
  replaceDeck(
    {'markdown': _Field.text, 'index': _Field.integer},
    {'ink': _Field.object},
  ),
  ink({'index': _Field.integer, 'strokes': _Field.objects}),
  inkLive({'index': _Field.integer, 'stroke': _Field.objectOrNull}),
  laser({'index': _Field.integer, 'point': _Field.pointOrNull}),
  question({'index': _Field.integer, 'view': _Field.objectOrNull}),
  chartHover(
    {'index': _Field.integer, 'hover': _Field.objectOrNull},
    {'seq': _Field.integer},
  ),
  costTick(
    {'minor': _Field.integer, 'currency': _Field.text},
    {'run': _Field.integer, 'eur': _Field.integer},
  ),
  timelineView({'index': _Field.integer, 'fraction': _Field.number}),
  tableUpdate(
    {'slideIndex': _Field.integer, 'tableRows': _Field.rows},
    {'seq': _Field.integer, 'alignments': _Field.strings},
  ),
  checklistUpdate(
    {
      'slideIndex': _Field.integer,
      'bullets': _Field.strings,
      'bullets2': _Field.strings,
    },
    {'seq': _Field.integer},
  ),
  docUpdate(
    {'index': _Field.integer, 'markdown': _Field.text, 'rev': _Field.integer},
    {'seq': _Field.integer},
  ),
  mermaidView({
    'index': _Field.integer,
    'scale': _Field.number,
    'fx': _Field.number,
    'fy': _Field.number,
  }),
  videoPlayback({
    'index': _Field.integer,
    'seq': _Field.integer,
    'playing': _Field.flag,
  });

  const AudienceMethod(this._required, [this._optional = const {}]);

  final Map<String, _Field> _required;
  final Map<String, _Field> _optional;
  static final _members = values.asNameMap();

  Future<Object?> send(Map<String, Object?> arguments) =>
      _send(audienceChannel, name, arguments, _required, _optional);

  static WindowMessage<AudienceMethod>? decode(MethodCall call) {
    final method = _members[call.method];
    if (method == null) return _reject('Onbekend bericht aan het publiek');
    return _decode(method, call.arguments, method._required, method._optional);
  }
}

/// Gebeurtenissen die het publieksvenster aan de presentator doorgeeft.
enum PresenterMethod {
  ready(),
  next(),
  prev(),
  exit(),
  key(
    {'keyId': _Field.integer},
    {'meta': _Field.flag, 'control': _Field.flag, 'shift': _Field.flag},
  ),
  audioComplete(), // Oud bericht, vervangen door mediaComplete.
  mediaComplete({'index': _Field.integer, 'kind': _Field.mediaKind}),
  checklistToggle({
    'slideIndex': _Field.integer,
    'column': _Field.integer,
    'itemIndex': _Field.integer,
  }),
  answerSelected({'slideIndex': _Field.integer, 'optionIndex': _Field.integer}),
  answerSubmit({'slideIndex': _Field.integer}),
  chartHover(
    {'index': _Field.integer, 'hover': _Field.objectOrNull},
    {'seq': _Field.integer},
  );

  const PresenterMethod([this._required = const {}, this._optional = const {}]);

  final Map<String, _Field> _required;
  final Map<String, _Field> _optional;
  static final _members = values.asNameMap();

  Future<Object?> send([Map<String, Object?>? arguments]) =>
      _send(presenterChannel, name, arguments, _required, _optional);

  static WindowMessage<PresenterMethod>? decode(MethodCall call) {
    final method = _members[call.method];
    if (method == null) return _reject('Onbekend bericht aan de presentator');
    return _decode(method, call.arguments, method._required, method._optional);
  }
}

const audienceChannel = WindowMethodChannel(
  'ocideck/audience',
  mode: ChannelMode.unidirectional,
);

const presenterChannel = WindowMethodChannel(
  'ocideck/presenter',
  mode: ChannelMode.unidirectional,
);

typedef WindowMessage<T extends Enum> = ({
  T method,
  Map<String, Object?> arguments,
});

WindowMessage<T>? _decode<T extends Enum>(
  T method,
  Object? raw,
  Map<String, _Field> required,
  Map<String, _Field> optional,
) {
  final arguments = _validate(method.name, raw, required, optional);
  return arguments == null ? null : (method: method, arguments: arguments);
}

Future<Object?> _send(
  WindowMethodChannel channel,
  String method,
  Map<String, Object?>? arguments,
  Map<String, _Field> required,
  Map<String, _Field> optional,
) {
  if (_validate(method, arguments, required, optional) == null) {
    return Future.error(FormatException('Ongeldige lading voor $method'));
  }
  return channel.invokeMethod<Object?>(method, arguments);
}

Map<String, Object?>? _validate(
  String method,
  Object? raw,
  Map<String, _Field> required,
  Map<String, _Field> optional,
) {
  if (raw == null && required.isEmpty) return const {};
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    return _reject('$method verwacht een object');
  }
  for (final MapEntry(:key, :value) in required.entries) {
    if (!raw.containsKey(key) || !value.accepts(raw[key])) {
      return _reject('$method: ongeldig of ontbrekend veld $key');
    }
  }
  for (final MapEntry(:key, :value) in optional.entries) {
    if (raw[key] case final Object field when !value.accepts(field)) {
      return _reject('$method: ongeldig veld $key');
    }
  }
  return raw.cast<String, Object?>();
}

Null _reject(String message) {
  final error = FormatException(message);
  if (kDebugMode) throw error;
  logError('Beamerprotocol', error);
  return null;
}

enum _Field {
  integer,
  number,
  flag,
  text,
  strings,
  object,
  objectOrNull,
  objects,
  pointOrNull,
  rows,
  mediaKind;

  bool accepts(Object? value) => switch (this) {
    integer => value is num && value.isFinite && value == value.truncate(),
    number => _finiteNumber(value),
    flag => value is bool,
    text => value is String,
    strings => value is List && value.every((entry) => entry is String),
    object => _object(value),
    objectOrNull => value == null || _object(value),
    objects => value is List && value.every(_object),
    pointOrNull =>
      value == null ||
          (value is List && value.length == 2 && value.every(_finiteNumber)),
    rows => value is List && value.every((row) => row is List),
    mediaKind => value == 'audio' || value == 'video',
  };
}

bool _finiteNumber(Object? value) => value is num && value.isFinite;
bool _object(Object? value) =>
    value is Map && value.keys.every((k) => k is String);
