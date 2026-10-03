/// Pure-Dart core of OciDeck form documents: the marker grammar, the rule engine
/// and the submission package. **No Flutter, no `dart:io`, no `dart:ui`**, so the
/// desktop app, the web form shell and a standalone Dart server can share it.
///
/// Design: `docs/design/FORM_INTAKE.md` in the OciDeck repository. What exists so
/// far: [parseForm] turns a template into a [FormSpec] (§4.3, §4.4); [parseAnswer]
/// and [extractAnswers] read answers out of their zones and [applyAnswer] writes
/// one back; [validateAnswer] and
/// [validateForm] judge them; [templateTextIssues] checks that the template-owned
/// text of a submission is still the published one. The package, sealing and the
/// image probe come next.
library;

export 'src/form_answer_safety.dart';
export 'src/form_answer_writer.dart';
export 'src/form_answers.dart';
export 'src/form_base32.dart';
export 'src/form_bech32.dart';
export 'src/form_blocks.dart';
export 'src/form_bundle.dart';
export 'src/form_compile.dart';
export 'src/form_counts.dart';
export 'src/form_editor_card.dart';
export 'src/form_field_types.dart';
export 'src/form_fill.dart';
export 'src/form_image.dart';
export 'src/form_issue.dart';
export 'src/form_jcs.dart';
export 'src/form_maker_check.dart';
export 'src/form_parser.dart' show parseForm;
export 'src/form_package.dart';
export 'src/form_patterns.dart';
export 'src/form_recovery_key.dart';
export 'src/form_register.dart';
export 'src/form_review.dart';
export 'src/form_rule_values.dart';
export 'src/form_seal.dart';
export 'src/form_source.dart';
export 'src/form_spec.dart';
export 'src/form_team.dart';
export 'src/form_template_text.dart';
export 'src/form_validator.dart';
export 'src/form_words.dart';
export 'src/intake_bodies.dart';
export 'src/intake_protocol.dart';
export 'src/intake_request.dart';
export 'src/intake_routes.dart';
export 'src/rules_version.dart';
