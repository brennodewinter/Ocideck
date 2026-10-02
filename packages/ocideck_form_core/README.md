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

A form being filled is one immutable value, so a screen is a function of it:

```dart
final fill = (FormFill.open(text) as FormFillReady).fill;
fill.items;                 // template text, headings, the notice, each field — in order
fill.problemsOf('naam');    // what is wrong with one answer
fill.canSend;               // no field has an error
final next = fill.setAnswer('naam', FormAnswerValue(text: 'Sari'));  // FormFillChanged | FormFillRefused
```

Images are the one thing that needs I/O, so what is known about a file arrives as
input (`FormImageFact`); without it an image is `image-unchecked`, never silently fine.
The counters and patterns are pinned by `test/fixtures/form_vectors.json`.

A filled form travels as a plain zip (FORM_INTAKE.md §5.2–§5.4). `buildFormPackage` writes
it deterministically; `readFormPackage` is the organiser's strict reader — it never throws,
and refuses (with every problem named) what is not exactly a package this engine would write:

```dart
final zip = buildFormPackage(
  submission: text, template: published, spec: spec, images: photos,
  submissionId: newFormId(Random.secure()), created: today, clientRules: kFormRulesVersion,
);
switch (readFormPackage(zip)) {
  case FormPackageOpened(:final submission, :final manifest, :final images): // verified
  case FormPackageRefused(:final problems):                                  // nothing read
}
```

The organiser judges what arrives against the **published** form, never the rules in the
submission itself (FORM_INTAKE.md §4.11 run 3, §7.2):

```dart
final review = reviewFormPackage(opened, publishedTexts);   // opened: FormPackageOpened
review.acceptable;        // no error; warnings only inform
review.problems;          // the form, the template text, the consent record, each field
review.images;            // the photos as they are to be kept — cleaned again
review.strippedAgain;     // where the client had left something in
```

Sealing (`age`) and the signed bundle follow (FORM_INTAKE.md §12).

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
