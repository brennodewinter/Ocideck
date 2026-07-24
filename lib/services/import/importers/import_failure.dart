/// A recoverable import failure, reported through `Result` rather than thrown.
///
/// [message] is user-facing (and localised by the UI layer); [cause] carries
/// the original exception for diagnostics when available.
class ImportFailure {
  const ImportFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
