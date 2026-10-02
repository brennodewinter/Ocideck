# ocideck_form_core

Pure-Dart core of OciDeck **form documents**: the marker grammar, the rule engine
and the submission package. No Flutter, no `dart:io`, no `dart:ui` — so the desktop
app, the web form shell and a standalone Dart server can share one implementation.

Design: [`docs/design/FORM_INTAKE.md`](../../docs/design/FORM_INTAKE.md) (§4.10 for
the engine, §16 for the file map). The package is first-party and not published
(`publish_to: none`); the app consumes it as a path dependency.

## What it does so far

```dart
import 'package:ocideck_form_core/ocideck_form_core.dart';

final result = parseForm(markdown);   // never throws
switch (result) {
  case NotAForm():                    // an ordinary document
  case ParsedForm(:final spec, :final notes):
    // spec.fields, spec.notice, spec.intro … each with offsets into `markdown`
  case BrokenForm(:final problems):   // every author error found, capped at 100
}
```

Answers and validation work on top of that:

```dart
final answers = extractAnswers(published, submissionText);   // against the PUBLISHED form
final issues = [
  ...validateForm(published, answers, imageFacts: facts),     // pure, synchronous
  ...templateTextIssues(publishedText, submissionText),       // consent text etc. intact?
];
if (formIssuesBlock(issues)) { /* an error: do not send / needs fixing */ }
```

Writing an answer is the inverse, and it changes **only the bytes of the answer zone**:

```dart
final edited = applyAnswer(text, spec, 'naam', FormAnswerValue(text: 'Sari'));
switch (edited) {
  case FormEdited(:final text, :final spec):   // the new document and its new spec
  case FormEditRefused(:final problem):        // nothing written: the answer would
}                                              // have changed the form itself
```

Images are the one thing that needs I/O, so what is known about a file arrives as
input (`FormImageFact`); without it an image is `image-unchecked`, never silently fine.
The counters and patterns are pinned by `test/fixtures/form_vectors.json`.

The package, sealing and the image probe follow (FORM_INTAKE.md §12).

## Working on it

```sh
make test-packages     # pub get + dart test + the coverage floor, per package
make check-packages    # the static rules (no Flutter/dart:io, licence, SDK constraint)
```

`dart format` and `flutter analyze` at the repository root already cover this folder,
and a `package:flutter` import fails analysis here by construction.

## Licence

EUPL-1.2, the same as the rest of the repository (`LICENSE` is a copy of the root
`LICENSE.md`; `make check-packages` keeps the two identical).
