/// Pure-Dart core of OciDeck form documents: the marker grammar, the rule engine
/// and the submission package. **No Flutter, no `dart:io`, no `dart:ui`**, so the
/// desktop app, the web form shell and a standalone Dart server can share it.
///
/// Design: `docs/design/FORM_INTAKE.md` in the OciDeck repository. What exists so
/// far is the reading side: [parseForm] turns a template into a [FormSpec] (§4.3,
/// §4.4); answers, validation and the package come next.
library;

export 'src/form_blocks.dart';
export 'src/form_field_types.dart';
export 'src/form_issue.dart';
export 'src/form_parser.dart' show parseForm;
export 'src/form_rule_values.dart';
export 'src/form_source.dart';
export 'src/form_spec.dart';
export 'src/rules_version.dart';
