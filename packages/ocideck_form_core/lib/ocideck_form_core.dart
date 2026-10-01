/// Pure-Dart core of OciDeck form documents: the marker grammar, the rule engine
/// and the submission package. **No Flutter, no `dart:io`, no `dart:ui`**, so the
/// desktop app, the web form shell and a standalone Dart server can share it.
///
/// Design: `docs/design/FORM_INTAKE.md` in the OciDeck repository.
library;

export 'src/rules_version.dart';
