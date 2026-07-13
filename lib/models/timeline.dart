/// Timeline-slide model.
///
/// A timeline is, at heart, a list of dated events — so the events themselves
/// stay in [Slide.bullets] as plain, human-readable Marp list items using the
/// `marker :: title :: description` convention. That keeps the `.md` a normal
/// Markdown list (it renders as a list in plain Marp too) and means no JSON
/// block is needed. The visual layout and animation are *presentation* options,
/// not content, so they round-trip as `_class` tokens
/// (`timeline-horizontal` / `timeline-vertical` / `timeline-steps` /
/// `timeline-static`) and live on [Slide.timelineLayout] / [Slide.timelineReveal].
library;

/// Field separator inside a single timeline bullet: `marker :: title :: desc`.
/// The surrounding spaces keep it readable and unambiguous in the raw `.md`.
const String timelineFieldSeparator = ' :: ';

/// Upper bound on events so a pathological deck can't make the painter crawl.
const int timelineMaxEvents = 12;

/// Default draw-on-enter duration for the whole timeline.
const int timelineDefaultAnimationDurationMs = 1600;

/// Bounds on the configurable draw-on-enter duration (faster ↔ slower). The
/// ceiling matches cockpitMaxAnimationDurationMs so a timeline can build up in
/// the same maximum 30s as a cockpit.
const int timelineMinAnimationDurationMs = 400;
const int timelineMaxAnimationDurationMs = 30000;

/// Clamp a stored/edited duration into the allowed range.
int clampTimelineDuration(int ms) =>
    ms.clamp(timelineMinAnimationDurationMs, timelineMaxAnimationDurationMs);

/// How the timeline arranges its events on the slide.
enum TimelineLayout {
  /// Horizontal rail for short timelines, vertical spine for longer ones.
  auto,

  /// Always a horizontal rail with cards alternating above/below.
  horizontal,

  /// Always a central vertical spine with cards alternating left/right.
  vertical,
}

/// How the timeline animates while presenting.
enum TimelineReveal {
  /// The whole timeline draws itself in, staggered, when the slide opens.
  onEnter,

  /// Each click reveals one further event (driven by the presenter).
  steps,

  /// No animation — everything is shown immediately.
  instant,
}

/// A single timeline entry. [marker] is the date/phase label (e.g. a year),
/// [title] the headline, [description] an optional one-liner. All are optional
/// individually; an event with no text at all is considered empty.
class TimelineEvent {
  final String marker;
  final String title;
  final String description;

  const TimelineEvent({
    this.marker = '',
    this.title = '',
    this.description = '',
  });

  bool get isEmpty =>
      marker.trim().isEmpty &&
      title.trim().isEmpty &&
      description.trim().isEmpty;

  /// Parse one stored bullet (`marker :: title :: description`). Leading
  /// indentation, if any, is stripped. Missing trailing fields are tolerated:
  /// a single segment is treated as the title.
  factory TimelineEvent.fromBullet(String raw) {
    final text = raw.replaceFirst(RegExp(r'^[\t ]+'), '').trim();
    final parts = text.split(timelineFieldSeparator);
    if (parts.length == 1) {
      return TimelineEvent(title: parts[0].trim());
    }
    if (parts.length == 2) {
      return TimelineEvent(marker: parts[0].trim(), title: parts[1].trim());
    }
    return TimelineEvent(
      marker: parts[0].trim(),
      title: parts[1].trim(),
      description: parts.sublist(2).join(timelineFieldSeparator).trim(),
    );
  }

  /// Serialize back to the canonical bullet form, dropping trailing empty
  /// fields so simple events stay simple in the `.md`.
  String toBullet() {
    if (description.trim().isNotEmpty) {
      return '$marker$timelineFieldSeparator$title$timelineFieldSeparator$description';
    }
    if (marker.trim().isNotEmpty) {
      return '$marker$timelineFieldSeparator$title';
    }
    return title;
  }

  TimelineEvent copyWith({
    String? marker,
    String? title,
    String? description,
  }) => TimelineEvent(
    marker: marker ?? this.marker,
    title: title ?? this.title,
    description: description ?? this.description,
  );
}

/// Parse the event list from a slide's bullets, dropping empty rows and
/// capping at [timelineMaxEvents].
List<TimelineEvent> parseTimelineEvents(List<String> bullets) => bullets
    .map(TimelineEvent.fromBullet)
    .where((e) => !e.isEmpty)
    .take(timelineMaxEvents)
    .toList();

/// Serialize events back to bullet strings for storage in [Slide.bullets].
List<String> timelineEventsToBullets(List<TimelineEvent> events) =>
    events.map((e) => e.toBullet()).toList();

/// The starter timeline seeded into a freshly created slide.
List<TimelineEvent> defaultTimelineEvents() => const [
  TimelineEvent(
    marker: '2019',
    title: 'Oprichting',
    description: 'Het begin van het verhaal.',
  ),
  TimelineEvent(
    marker: '2021',
    title: 'Doorbraak',
    description: 'De eerste grote mijlpaal.',
  ),
  TimelineEvent(
    marker: '2023',
    title: 'Groei',
    description: 'Opschalen naar een groter publiek.',
  ),
  TimelineEvent(
    marker: 'Nu',
    title: 'Vandaag',
    description: 'Waar we nu staan.',
  ),
];

/// The seven project phases of the Penetration Testing Execution Standard
/// (PTES), as ready-to-load timeline events. Markers are the phase numbers and
/// the titles/descriptions are Dutch source text (freely editable after
/// loading); they are content, not localised UI, like other seeded slide text.
const List<TimelineEvent> ptesTimelinePhases = [
  TimelineEvent(
    marker: 'Fase 1',
    title: 'Voorafgaande afspraken',
    description: 'Scope, doelen, planning en spelregels vastleggen.',
  ),
  TimelineEvent(
    marker: 'Fase 2',
    title: 'Informatie verzamelen',
    description: 'Open bronnen en verkenning van de doelomgeving.',
  ),
  TimelineEvent(
    marker: 'Fase 3',
    title: 'Dreigingsmodellering',
    description: 'Relevante dreigingen en aanvalspaden in kaart brengen.',
  ),
  TimelineEvent(
    marker: 'Fase 4',
    title: 'Kwetsbaarheidsanalyse',
    description: 'Kwetsbaarheden identificeren en valideren.',
  ),
  TimelineEvent(
    marker: 'Fase 5',
    title: 'Exploitatie',
    description: 'Kwetsbaarheden actief benutten om toegang te verkrijgen.',
  ),
  TimelineEvent(
    marker: 'Fase 6',
    title: 'Post-exploitatie',
    description: 'Impact, reikwijdte en persistentie bepalen.',
  ),
  TimelineEvent(
    marker: 'Fase 7',
    title: 'Rapportage',
    description: 'Bevindingen, risico en aanbevelingen vastleggen.',
  ),
];

/// The `_class` tokens that encode the layout/animation options (the base
/// `timeline` token is emitted separately via the slide's marpClass).
List<String> timelineClassTokens(
  TimelineLayout layout,
  TimelineReveal reveal,
) => [
  if (layout == TimelineLayout.horizontal) 'timeline-horizontal',
  if (layout == TimelineLayout.vertical) 'timeline-vertical',
  if (reveal == TimelineReveal.steps) 'timeline-steps',
  if (reveal == TimelineReveal.instant) 'timeline-static',
];

/// All option tokens this slide type understands (for class-filtering and
/// validator allow-listing). Does not include the base `timeline` token.
const Set<String> timelineOptionTokens = {
  'timeline-horizontal',
  'timeline-vertical',
  'timeline-steps',
  'timeline-static',
};

bool isTimelineOptionToken(String token) =>
    timelineOptionTokens.contains(token);

TimelineLayout timelineLayoutFromTokens(Iterable<String> tokens) {
  if (tokens.contains('timeline-vertical')) return TimelineLayout.vertical;
  if (tokens.contains('timeline-horizontal')) return TimelineLayout.horizontal;
  return TimelineLayout.auto;
}

TimelineReveal timelineRevealFromTokens(Iterable<String> tokens) {
  if (tokens.contains('timeline-steps')) return TimelineReveal.steps;
  if (tokens.contains('timeline-static')) return TimelineReveal.instant;
  return TimelineReveal.onEnter;
}
