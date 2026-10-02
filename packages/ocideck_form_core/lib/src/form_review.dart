/// The organiser's judgement of a received package (FORM_INTAKE.md §4.11 run 3, §7.2).
///
/// The package is *data from a client the organiser does not trust*: a modified or
/// merely old client could have weakened a rule by editing its own copy of the form.
/// So nothing here asks `submission.md` what the rules are. The rules come from the
/// **published** form the organiser holds (§7.1), found by the hash the manifest
/// names; the submission is judged against them, and the text outside the answers
/// must be byte-for-byte that form's (the consent texts live there).
///
/// A failure is a list of problems for the Inbox ("needs fixing"), never a silent
/// drop. The function is pure: the photos arrive as bytes and leave as bytes, and the
/// one check that needs a decoder (a photo that really decodes) is an input, because
/// this package has none.
library;

import 'dart:typed_data';

import 'form_answers.dart';
import 'form_image.dart';
import 'form_issue.dart';
import 'form_package.dart';
import 'form_parser.dart';
import 'form_spec.dart';
import 'form_template_text.dart';
import 'form_validator.dart';

/// What the organiser concluded about one package.
class FormReview {
  const FormReview({
    required this.manifest,
    required this.problems,
    this.published,
    this.spec,
    this.answers,
    this.images = const {},
    this.strippedAgain = const {},
    this.unreferencedImages = const [],
  });

  final FormPackageManifest manifest;

  /// Everything wrong or worth saying, in this order: the form the package names,
  /// the template text, then each field. An *error* means the submission needs fixing.
  final List<FormProblem> problems;

  /// The text of the published form the submission was judged against, or `null`
  /// when the package names no form the organiser holds (`template-unknown`).
  final String? published;

  /// The spec of [published]; `null` whenever [published] is.
  final FormSpec? spec;

  /// The answers as read against [spec].
  final FormAnswers? answers;

  /// The photos as they are to be kept: every one cleaned again, because the
  /// respondent's client is not trusted. For a photo that had nothing left to remove
  /// these are the bytes that were received.
  final Map<String, Uint8List> images;

  /// Per photo, what the second cleaning still found — only the photos where it found
  /// something. A GPS position here means the client did not strip, or lied.
  final Map<String, FormImageRemoved> strippedAgain;

  /// Photos in the package that no answer refers to. Nothing blocks on them; the
  /// Inbox shows them, because a file no answer mentions is a file nobody asked for.
  final List<String> unreferencedImages;

  /// Whether the submission may be accepted into the collection: no problem is an
  /// error. (A form the organiser does not hold, or cannot use, always has one.)
  /// Warnings only inform.
  bool get acceptable => !formIssuesBlock(problems);
}

/// Judges [package] against the published forms in [published] (the whole text of
/// each version and language the organiser holds under `forms/`).
///
/// [undecodable] are the paths of photos a real decode refused; the caller decodes
/// (this package cannot), and they are reported as a format problem.
FormReview reviewFormPackage(
  FormPackageOpened package,
  List<String> published, {
  Set<String> undecodable = const {},
}) {
  final manifest = package.manifest;
  final found = _publication(manifest, published);
  if (found == null) {
    return FormReview(
      manifest: manifest,
      problems: [
        FormProblem(
          FormIssueCode.templateUnknown,
          facts: {
            'form': manifest.formId,
            'version': manifest.formVersion,
            'sha256': manifest.templateSha256,
          },
        ),
      ],
    );
  }

  final problems = <FormProblem>[];
  final text = found.text;
  final parsed = parseForm(text);
  if (parsed is! ParsedForm) {
    return FormReview(
      manifest: manifest,
      published: text,
      problems: [
        FormProblem(
          FormIssueCode.structureDamaged,
          facts: const {'reason': 'published-form'},
        ),
      ],
    );
  }
  if (!parsed.canFill) {
    return FormReview(
      manifest: manifest,
      published: text,
      problems: [
        FormProblem(
          FormIssueCode.rulesTooNew,
          facts: {'form': manifest.formId, 'rules': parsed.spec.rules},
        ),
      ],
    );
  }
  final spec = parsed.spec;

  if (!found.byHash) {
    // Same form and version, but not the text the manifest hashed: the client worked
    // from a copy of the form that is not the published one.
    problems.add(
      FormProblem(
        FormIssueCode.templateTextAltered,
        facts: const {'reason': 'hash'},
      ),
    );
  }
  problems.addAll(templateTextIssues(text, package.submission));

  final answers = extractAnswers(spec, package.submission);
  problems.addAll(_consentIssues(spec, text, package));

  final referenced = {
    for (final answer in answers.byId.values)
      for (final image in answer.images) image.path,
  };
  final photos = _photos(package.images, undecodable);
  // An answer that names a photo the package does not hold is `image-missing-file`,
  // which needs a fact saying so: no fact at all reads as "not checked".
  for (final path in referenced) {
    photos.facts.putIfAbsent(path, () => const FormImageFact(exists: false));
  }
  problems.addAll(validateForm(spec, answers, imageFacts: photos.facts));

  return FormReview(
    manifest: manifest,
    published: text,
    spec: spec,
    answers: answers,
    problems: problems,
    images: photos.kept,
    strippedAgain: photos.stripped,
    unreferencedImages: [
      for (final path in package.images.keys)
        if (!referenced.contains(path)) path,
    ],
  );
}

typedef _Found = ({String text, bool byHash});

/// The published text the manifest means: the one it hashed or, failing that, one
/// with the same form id and version (then the hash is the problem).
_Found? _publication(FormPackageManifest manifest, List<String> published) {
  for (final text in published) {
    if (formTemplateHash(text) == manifest.templateSha256) {
      return (text: text, byHash: true);
    }
  }
  for (final text in published) {
    if (parseForm(text) case ParsedForm(:final spec)) {
      if (spec.id == manifest.formId && spec.version == manifest.formVersion) {
        return (text: text, byHash: false);
      }
    }
  }
  return null;
}

/// The manifest's consent record is a cross-check, not the proof (§5.3): the consent
/// text's hash is recomputed from the *published* form, and the fields the manifest
/// says were accepted must be the ones the answers accept.
List<FormProblem> _consentIssues(
  FormSpec spec,
  String published,
  FormPackageOpened package,
) {
  final expected = {
    for (final c in consentsAccepted(
      spec: spec,
      template: published,
      submission: package.submission,
      day: package.manifest.created,
    ))
      '${c.field}:${c.textSha256}',
  };
  final recorded = {
    for (final c in package.manifest.consent) '${c.field}:${c.textSha256}',
  };
  if (expected.length == recorded.length && expected.containsAll(recorded)) {
    return const [];
  }
  return [
    FormProblem(
      FormIssueCode.templateTextAltered,
      facts: const {'reason': 'consent'},
    ),
  ];
}

({
  FormImageFacts facts,
  Map<String, Uint8List> kept,
  Map<String, FormImageRemoved> stripped,
})
_photos(Map<String, Uint8List> received, Set<String> undecodable) {
  final facts = <String, FormImageFact>{};
  final kept = <String, Uint8List>{};
  final stripped = <String, FormImageRemoved>{};
  for (final MapEntry(key: path, value: bytes) in received.entries) {
    final report = cleanImage(bytes);
    if (report == null || undecodable.contains(path)) {
      kept[path] = bytes;
      facts[path] = FormImageFact(bytes: bytes.length, format: 'unknown');
      continue;
    }
    kept[path] = report.bytes;
    if (report.removed.any) stripped[path] = report.removed;
    facts[path] = FormImageFact(
      displayedWidth: report.displayedWidth,
      bytes: report.bytes.length,
      format: report.kind.extension,
      unverified: report.unverified,
    );
  }
  return (facts: facts, kept: kept, stripped: stripped);
}
