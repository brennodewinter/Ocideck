/// Compile: from the submissions an organiser accepted to one document (FORM_INTAKE.md
/// §7.5). A **chapter template** is an ordinary Markdown text with `{field-id}`
/// placeholders; compile applies it to each selected submission and joins the chapters.
///
/// It is **not** the `{field}` resolver of a running head or foot: that one escapes
/// every Markdown punctuation character, turns a line break into a literal `\n` and cuts
/// a value at 4096 characters — a 40-recipe book would stop at six recipes with an
/// ellipsis, and a table would become escaped pipes. This writer has its own rules:
///
/// * an answer is inserted **as the Markdown it already is** — it passed the whitelist
///   of §4.6 when the submission was judged — per field type, and **nothing is cut**;
/// * each inserted answer is checked for **balanced code fences**, so one bad answer
///   cannot turn every later chapter into a code block;
/// * a line whose placeholders are **all empty**, and that holds nothing else but
///   Markdown emphasis or a heading or list marker, is dropped, so an optional field
///   does not leave `## ` or `*  *` behind (a placeholder next to words of its own,
///   `*Sari — {rol}*`, keeps its words: write an optional part on a line of its own);
/// * photos are copied to `images/<sid>-<field>-<n>.<ext>` and their paths rewritten;
///   the chapter names the photos it needs ([ChapterImage]) and the caller copies them;
/// * a submission that was **withdrawn is never compiled**, whatever else is asked.
///
/// The vocabulary is closed: selection, ordering by one field, a grouping heading by one
/// field, empty-line dropping. No expressions, no nesting. Anything more is edited by
/// hand in the resulting document.
library;

import 'form_answers.dart';
import 'form_spec.dart';

/// The grammar of a placeholder: a field id between braces.
final RegExp kChapterPlaceholder = RegExp(r'\{([a-z][a-z0-9-]*)\}');

/// A chapter template: its text and the placeholders it uses.
class ChapterTemplate {
  ChapterTemplate(this.text) : placeholders = _placeholdersOf(text);

  final String text;

  /// The field ids used outside fenced code, in the order of first use.
  final List<String> placeholders;

  /// The placeholders that are not a field of [spec]: a template that names one is
  /// refused rather than compiled into a book with `{typo}` in every chapter.
  List<String> unknownIn(FormSpec spec) => [
    for (final id in placeholders)
      if (spec.fieldById(id) == null) id,
  ];
}

List<String> _placeholdersOf(String text) {
  final seen = <String>{};
  _eachOutsideFence(text, (line) {
    for (final m in kChapterPlaceholder.allMatches(line)) {
      seen.add(m.group(1)!);
    }
  });
  return seen.toList();
}

/// A photo a chapter needs: where it is in the submission and where it goes in the
/// book (both relative paths).
class ChapterImage {
  const ChapterImage({
    required this.sid,
    required this.fieldId,
    required this.from,
    required this.to,
    required this.alt,
    this.credit,
  });

  final String sid;
  final String fieldId;

  /// `images/<field>-<n>.<ext>` in the submission's folder.
  final String from;

  /// `images/<sid>-<field>-<n>.<ext>` beside the book.
  final String to;
  final String alt;

  /// The credit the respondent gave (the title of the image), or `null`.
  final String? credit;
}

/// One chapter, rendered.
class RenderedChapter {
  const RenderedChapter(this.markdown, this.images);

  final String markdown;
  final List<ChapterImage> images;
}

/// A submission offered to compile.
class CompileSubmission {
  const CompileSubmission({
    required this.sid,
    required this.answers,
    this.withdrawn = false,
  });

  final String sid;
  final FormAnswers answers;

  /// The respondent withdrew it: compile leaves it out whatever else is asked (§7.3).
  final bool withdrawn;
}

/// The result of [compileBook].
sealed class BookResult {
  const BookResult();
}

/// The book: the document, the photos to copy, and which submissions are in it.
class BookCompiled extends BookResult {
  const BookCompiled({
    required this.markdown,
    required this.images,
    required this.included,
    required this.withdrawn,
  });

  final String markdown;
  final List<ChapterImage> images;

  /// The submission numbers in the book, in the order of its chapters.
  final List<String> included;

  /// The numbers left out because they were withdrawn.
  final List<String> withdrawn;
}

/// The template names a placeholder that is no field of the form.
class BookRefused extends BookResult {
  const BookRefused(this.unknown);

  final List<String> unknown;
}

/// Compiles [submissions] into one document with [template].
///
/// [orderBy] is a field id: chapters are ordered by that field's text (compared as
/// lower-case text, the same in every language; an empty value last, a tie in the order
/// the submissions came). [groupBy] is a field id too: a heading `## <value>` goes
/// before the first chapter of each run of equal values — group by a field and order by
/// the same field, or the runs are as they come. Both must be fields of [spec].
BookResult compileBook({
  required ChapterTemplate template,
  required FormSpec spec,
  required List<CompileSubmission> submissions,
  String? orderBy,
  String? groupBy,
}) {
  final unknown = template.unknownIn(spec);
  if (unknown.isNotEmpty) return BookRefused(unknown);

  final withdrawn = [
    for (final s in submissions)
      if (s.withdrawn) s.sid,
  ];
  var chosen = [
    for (final s in submissions)
      if (!s.withdrawn) s,
  ];
  // A field the form does not have has no value in any submission: every key is empty
  // and the order is the order they came in. No guard needed.
  if (orderBy != null) chosen = _ordered(chosen, orderBy);

  final out = <String>[];
  final images = <ChapterImage>[];
  String? previousGroup;
  for (final s in chosen) {
    if (groupBy != null) {
      final group = _plain(s.answers.byId[groupBy]);
      if (group.isNotEmpty && group != previousGroup) out.add('## $group');
      previousGroup = group;
    }
    final chapter = renderChapter(
      template: template,
      spec: spec,
      answers: s.answers,
      sid: s.sid,
    );
    out.add(chapter.markdown);
    images.addAll(chapter.images);
  }
  return BookCompiled(
    markdown: out.isEmpty ? '' : '${out.join('\n\n')}\n',
    images: images,
    included: [for (final s in chosen) s.sid],
    withdrawn: withdrawn,
  );
}

List<CompileSubmission> _ordered(List<CompileSubmission> list, String field) {
  final keyed = [
    for (var i = 0; i < list.length; i++)
      (i, _plain(list[i].answers.byId[field]).toLowerCase(), list[i]),
  ];
  keyed.sort((a, b) {
    final x = a.$2;
    final y = b.$2;
    // An empty value goes last, however the others sort.
    if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
    final byValue = x.compareTo(y);
    return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
  });
  return [for (final k in keyed) k.$3];
}

/// Renders one chapter of [template] for the submission [sid].
RenderedChapter renderChapter({
  required ChapterTemplate template,
  required FormSpec spec,
  required FormAnswers answers,
  required String sid,
}) {
  final images = <ChapterImage>[];
  final values = <String, String>{};
  for (final id in template.placeholders) {
    final field = spec.fieldById(id);
    final answer = answers.byId[id];
    if (field == null || answer == null) {
      values[id] = '';
      continue;
    }
    values[id] = _balancedFences(_insertion(field, answer, sid, images));
  }

  final out = <String>[];
  var inFence = false;
  String? fence;
  for (final line in template.text.replaceAll('\r\n', '\n').split('\n')) {
    final marker = _fenceMarker(line);
    if (marker != null) {
      if (!inFence) {
        inFence = true;
        fence = marker;
      } else if (marker == fence) {
        inFence = false;
      }
      out.add(line);
      continue;
    }
    if (inFence) {
      out.add(line);
      continue;
    }
    final used = [
      for (final m in kChapterPlaceholder.allMatches(line)) m.group(1)!,
    ];
    if (used.isNotEmpty && used.every((id) => values[id]!.trim().isEmpty)) {
      if (_holdsOnlyMarkup(line.replaceAll(kChapterPlaceholder, ''))) continue;
    }
    out.add(
      line.replaceAllMapped(
        kChapterPlaceholder,
        (m) => values[m.group(1)!] ?? m.group(0)!,
      ),
    );
  }
  return RenderedChapter(out.join('\n').trimRight(), images);
}

/// What a line holds once its placeholders are gone: only whitespace and the Markdown
/// that would be left standing alone — emphasis, a heading, a quote or a list marker.
bool _holdsOnlyMarkup(String rest) => RegExp(r'^[\s*_#>+\-]*$').hasMatch(rest);

/// An answer as Markdown, per field type (§7.5). Nothing is cut.
String _insertion(
  FormFieldSpec field,
  FormAnswer answer,
  String sid,
  List<ChapterImage> images,
) {
  switch (field.type) {
    case 'consent':
      // The consent is a record in the manifest and the register, not text for a book.
      return '';
    case 'multichoice':
      return answer.items.join(', ');
    case 'list' || 'table':
      return answer.raw.replaceAll('\r\n', '\n').trim();
    case 'image':
      final lines = <String>[];
      for (var n = 0; n < answer.images.length; n++) {
        final image = answer.images[n];
        final ext = image.path.substring(image.path.lastIndexOf('.') + 1);
        final to = 'images/$sid-${field.id}-${n + 1}.$ext';
        images.add(
          ChapterImage(
            sid: sid,
            fieldId: field.id,
            from: image.path,
            to: to,
            alt: image.alt,
            credit: image.credit,
          ),
        );
        final title = image.credit == null || image.credit!.isEmpty
            ? ''
            : ' "${image.credit}"';
        lines.add('![${image.alt}]($to$title)');
      }
      return lines.join('\n\n');
    default:
      // text, number, date, choice, prose: the text as written.
      return (answer.text ?? '').replaceAll('\r\n', '\n').trim();
  }
}

/// The text of an answer on one line, for ordering and for a grouping heading.
String _plain(FormAnswer? answer) {
  if (answer == null) return '';
  final text = answer.items.isNotEmpty
      ? answer.items.join(', ')
      : (answer.text ?? '');
  return text.split('\n').first.trim();
}

// ── code fences ─────────────────────────────────────────────────────────────

final RegExp _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// The fence marker of [line] (its first three characters), or `null`.
String? _fenceMarker(String line) {
  final m = _fenceLine.firstMatch(line);
  return m == null ? null : m.group(1)![0] * 3;
}

void _eachOutsideFence(String text, void Function(String line) visit) {
  var inFence = false;
  String? fence;
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    final marker = _fenceMarker(line);
    if (marker != null) {
      if (!inFence) {
        inFence = true;
        fence = marker;
      } else if (marker == fence) {
        inFence = false;
      }
      continue;
    }
    if (!inFence) visit(line);
  }
}

/// [value] with any fence it leaves open closed again, so it cannot swallow what
/// follows it.
String _balancedFences(String value) {
  var open = false;
  String? fence;
  for (final line in value.split('\n')) {
    final marker = _fenceMarker(line);
    if (marker == null) continue;
    if (!open) {
      open = true;
      fence = marker;
    } else if (marker == fence) {
      open = false;
    }
  }
  return open ? '$value\n$fence' : value;
}
