/// Lightweight logging for failures the app deliberately swallows.
///
/// Many call sites here used to be bare `catch (_) {}` blocks. Swallowing was
/// usually the *right* behaviour — a broken sidecar, an unreadable file or an
/// unsupported platform must never crash a presentation — but the failure then
/// vanished without a trace, which made real bugs invisible. Routing these
/// through [logError]/[logWarning] keeps the fail-soft behaviour while making
/// the cause observable.
///
/// Records go to the `dart:developer` logging stream (DevTools / the VM
/// service), not stdout, so release builds stay quiet. Pass only an operation
/// description and the caught error object — never deck or file *contents*,
/// which can be personal data.
library;

import 'dart:developer' as developer;

const _name = 'ocideck';

// Severity levels mirror package:logging (WARNING = 900, SEVERE = 1000).
const int _levelWarning = 900;
const int _levelError = 1000;

/// An unexpected failure that was handled by falling back. [op] is a short
/// description of what was attempted, e.g. `'openDeck: read annotation sidecar'`.
void logError(String op, Object error, [StackTrace? stack]) {
  developer.log(
    op,
    name: _name,
    error: error,
    stackTrace: stack,
    level: _levelError,
  );
}

/// An expected-but-notable condition where the app fell back to a default
/// (e.g. an absent optional file, an unsupported platform capability). Lower
/// severity than [logError]; [error] is optional.
void logWarning(String op, [Object? error]) {
  developer.log(op, name: _name, error: error, level: _levelWarning);
}
