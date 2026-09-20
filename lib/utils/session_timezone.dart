// Wandklok-weergave van sessietijden (planning, issue #2123). De server
// stuurt `starts_at`/`ends_at` als UTC-moment plus de IANA-zone van de
// bijeenkomst; de deelnemer wil de tijd zien in de zone van de sessie én, als
// die afwijkt, in de eigen zone. Dart kent geen tzdb — `package:timezone`
// levert die gebundeld en volledig offline.

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _timezonesReady = false;

/// Laadt de gebundelde tzdb eenmalig (~600 kB, synchroon en offline).
void ensureSessionTimezones() {
  if (_timezonesReady) return;
  tzdata.initializeTimeZones();
  _timezonesReady = true;
}

/// De wandklok van [instant] in de sessiezone plus in de eigen zone.
/// [zoneKnown] is false bij een onbekende IANA-naam — de widget toont dan
/// alleen de eigen tijd. [sameZone] is true als beide weergaven hetzelfde
/// zijn; dan volstaat één regel.
class SessionClockView {
  const SessionClockView({
    required this.sessionStart,
    required this.sessionEnd,
    required this.localStart,
    required this.localEnd,
    required this.zoneKnown,
    required this.sameZone,
  });

  /// Wandklok in de sessiezone (of de eigen zone als die onbekend is).
  final DateTime sessionStart;
  final DateTime sessionEnd;

  /// Wandklok in de eigen (apparaat-)zone.
  final DateTime localStart;
  final DateTime localEnd;
  final bool zoneKnown;
  final bool sameZone;
}

SessionClockView sessionClockView(
  DateTime startsAt,
  DateTime endsAt,
  String zoneName,
) {
  ensureSessionTimezones();
  tz.Location? location;
  try {
    location = tz.getLocation(zoneName.trim());
  } on tz.LocationNotFoundException {
    location = null;
  }
  final localStart = startsAt.toLocal();
  final localEnd = endsAt.toLocal();
  final sessionStart = location == null
      ? localStart
      : tz.TZDateTime.from(startsAt, location);
  final sessionEnd = location == null
      ? localEnd
      : tz.TZDateTime.from(endsAt, location);
  bool sameClock(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
  return SessionClockView(
    sessionStart: sessionStart,
    sessionEnd: sessionEnd,
    localStart: localStart,
    localEnd: localEnd,
    zoneKnown: location != null,
    sameZone:
        sameClock(sessionStart, localStart) && sameClock(sessionEnd, localEnd),
  );
}
