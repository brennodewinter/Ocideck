/// Explicit result handling for the conversion pipeline.
///
/// Importers and the pipeline report recoverable failures as a [Result]
/// instead of throwing, so the caller (and the UI) can decide what to do —
/// skip a slide, ask the user, or abort. Exceptions are reserved for
/// programming errors; a malformed source file is an expected outcome, not a
/// crash.
sealed class Result<F, V> {
  const Result();
}

/// A successful result carrying a value [v].
final class Ok<F, V> extends Result<F, V> {
  const Ok(this.v);
  final V v;
}

/// A failed result carrying a typed failure [f] with context.
final class Err<F, V> extends Result<F, V> {
  const Err(this.f);
  final F f;
}

/// Convenience helpers to build results without naming the type arguments.
extension ResultConstruction on Never {
  static Result<F, V> ok<F, V>(V v) => Ok<F, V>(v);
  static Result<F, V> err<F, V>(F f) => Err<F, V>(f);
}

/// Work with a [Result] without switching on its type at every call site.
extension ResultOps<F, V> on Result<F, V> {
  /// True when this is an [Ok].
  bool get isOk => this is Ok<F, V>;

  /// True when this is an [Err].
  bool get isErr => this is Err<F, V>;

  /// The value if [Ok], otherwise `null`.
  V? get okValue => switch (this) {
    Ok(:final v) => v,
    Err() => null,
  };

  /// The failure if [Err], otherwise `null`.
  F? get errValue => switch (this) {
    Ok() => null,
    Err(:final f) => f,
  };

  /// Transform the value of an [Ok]; pass an [Err] through unchanged.
  Result<F, W> map<W>(W Function(V) fn) => switch (this) {
    Ok(:final v) => Ok<F, W>(fn(v)),
    Err(:final f) => Err<F, W>(f),
  };

  /// Chain a result-producing step on an [Ok]; pass an [Err] through.
  Result<F, W> andThen<W>(Result<F, W> Function(V) fn) => switch (this) {
    Ok(:final v) => fn(v),
    Err(:final f) => Err<F, W>(f),
  };
}
