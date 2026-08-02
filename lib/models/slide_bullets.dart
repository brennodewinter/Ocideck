// Part of the slide library — see slide.dart. Split out for the file-size
// ratchet: the bullet-list item encoding helpers (level, checklist and
// group-heading sentinels). They stay in the same library, so `Slide` and the
// markdown parser keep calling them straight, with no import change at any call
// site.
part of 'slide.dart';

int bulletLevel(String value) {
  var level = 0;
  while (level < value.length && value[level] == '\t') {
    level++;
  }
  return level;
}

String bulletText(String value) => value.substring(bulletLevel(value));

bool checklistItemChecked(String value) =>
    RegExp(r'^\[[xX]\]\s*').hasMatch(bulletText(value));

String checklistItemText(String value) =>
    bulletText(value).replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '');

String checklistBullet({
  required int level,
  required String text,
  required bool checked,
}) => '${'\t' * level}[${checked ? 'x' : ' '}] $text';

/// Sentinel that marks a bullet-list item as a **group heading** ("tussenkop"):
/// a labelled break that visually separates groups of bullets on one slide, so a
/// single bullets slide can be split into sections without splitting the slide.
///
/// It is a private-use codepoint stored inline at the start of the item's text
/// — mirroring the checklist `[x]` convention — so a heading is just another
/// entry in [Slide.bullets]. Ordering, drag-reorder, delete and the file
/// round-trip therefore all ride the existing list machinery: no parallel list
/// of positions to keep in sync. An empty label renders as a plain divider rule
/// (a break with no words). Group headings are always at level 0.
///
/// The codepoint is deliberately in the Unicode Private Use Area so it can never
/// collide with text a user actually types (the same reasoning as the caption
/// pipe sentinels in `markdown_service_helpers.dart`).
const String kGroupHeadingMarker = '\u{E010}';

/// Whether [value] is a group-heading item (see [kGroupHeadingMarker]).
bool isGroupHeading(String value) =>
    bulletText(value).startsWith(kGroupHeadingMarker);

/// The label of a group-heading item, or the plain bullet text when [value] is
/// an ordinary bullet. Empty for a wordless divider.
String groupHeadingText(String value) {
  final body = bulletText(value);
  return body.startsWith(kGroupHeadingMarker)
      ? body.substring(kGroupHeadingMarker.length)
      : body;
}

/// Builds a group-heading item carrying [text] (empty = a wordless divider).
String groupHeadingBullet(String text) => '$kGroupHeadingMarker$text';
