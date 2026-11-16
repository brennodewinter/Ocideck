// Budgetten voor onbetrouwbare serverinvoer (#2957). Bericht-, sessie- en
// resultaatgrenzen zijn onafhankelijk: veel kleine berichten zijn ook invoer.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const liveResponseLimitMessage = 'serverantwoord overschrijdt de live-limiet';

/// Signals an exceeded live response budget.
final class LiveResponseLimitExceeded implements Exception {
  const LiveResponseLimitExceeded();

  @override
  String toString() => liveResponseLimitMessage;
}

/// Independent message, session, queue and retained-result limits.
class LiveResponseLimits {
  const LiveResponseLimits({
    this.messageBytes = 256 * 1024,
    this.textBytes = 64 * 1024,
    this.words = 4096,
    this.sessionBytes = 64 * 1024 * 1024,
    this.messages = 250000,
    this.resultBytes = 8 * 1024 * 1024,
    this.segments = 100000,
    this.queuedBytes = 1024 * 1024,
    this.queuedMessages = 256,
  });

  final int messageBytes;
  final int textBytes;
  final int words;
  final int sessionBytes;
  final int messages;
  final int resultBytes;
  final int segments;
  final int queuedBytes;
  final int queuedMessages;
}

/// De snelle tekengrens begrenst ook de tijdelijke UTF-8-allocatie.
int checkedLiveTextBytes(String text, int maximum) {
  if (text.length > maximum) throw const LiveResponseLimitExceeded();
  final size = utf8.encode(text).length;
  if (size > maximum) throw const LiveResponseLimitExceeded();
  return size;
}

int checkedLiveFrameBytes(Object frame, LiveResponseLimits limits) {
  if (frame is String) {
    return checkedLiveTextBytes(frame, limits.messageBytes);
  }
  final size = frame is List<int> ? frame.length : 0;
  if (size > limits.messageBytes) throw const LiveResponseLimitExceeded();
  return size;
}

/// Accounts for incoming and retained data within one live operation.
class LiveResponseBudget {
  LiveResponseBudget(this.limits);

  final LiveResponseLimits limits;
  var _bytes = 0;
  var _messages = 0;
  var _resultBytes = 0;
  var _segments = 0;

  int admit(Object frame) {
    final bytes = checkedLiveFrameBytes(frame, limits);
    if (_messages >= limits.messages || bytes > limits.sessionBytes - _bytes) {
      throw const LiveResponseLimitExceeded();
    }
    _messages++;
    _bytes += bytes;
    return bytes;
  }

  void retainResult(String text) {
    final bytes = checkedLiveTextBytes(text, limits.textBytes);
    if (_segments >= limits.segments ||
        bytes > limits.resultBytes - _resultBytes) {
      throw const LiveResponseLimitExceeded();
    }
    _segments++;
    _resultBytes += bytes;
  }
}

class _QueuedLiveFrame {
  const _QueuedLiveFrame(this.value, this.bytes);
  final Object value;
  final int bytes;
}

/// Buffers live frames within explicit byte and message-count limits.
///
/// De transport luistert zelf door als de afnemer pauzeert. Daardoor blijft
/// de wachtrij begrensd, in plaats van de grens naar een socketbuffer te duwen.
/// Platform-WebSockets leveren al samengestelde berichten; die eerste
/// platformallocatie kan deze applicatielaag niet voorkomen.
class BoundedLiveInput {
  BoundedLiveInput({
    this.limits = const LiveResponseLimits(),
    required this.onLimit,
  }) : _budget = LiveResponseBudget(limits);

  final LiveResponseLimits limits;
  final void Function() onLimit;
  final LiveResponseBudget _budget;
  final _controller = StreamController<_QueuedLiveFrame>(sync: true);
  var _queuedBytes = 0;
  var _queuedMessages = 0;
  var _closed = false;

  late final Stream<Object> stream = _controller.stream.map((frame) {
    _queuedBytes -= frame.bytes;
    _queuedMessages--;
    return frame.value;
  });

  void add(Object frame) {
    if (_closed) return;
    try {
      final bytes = _budget.admit(frame);
      if (_queuedMessages >= limits.queuedMessages ||
          bytes > limits.queuedBytes - _queuedBytes) {
        throw const LiveResponseLimitExceeded();
      }
      // Kopieer binaire socketdata pas nadat de grens is getoetst.
      final owned = frame is List<int> ? Uint8List.fromList(frame) : frame;
      _queuedBytes += bytes;
      _queuedMessages++;
      _controller.add(_QueuedLiveFrame(owned, bytes));
    } on LiveResponseLimitExceeded catch (e, s) {
      addError(e, s);
      onLimit();
    }
  }

  void reject() {
    if (_closed) return;
    addError(const LiveResponseLimitExceeded());
    onLimit();
  }

  void addError(Object error, [StackTrace? stack]) {
    if (_closed) return;
    _controller.addError(error, stack);
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // Een gepauzeerde/ontbrekende afnemer mag socketcleanup niet blokkeren.
    unawaited(_controller.close());
  }
}
