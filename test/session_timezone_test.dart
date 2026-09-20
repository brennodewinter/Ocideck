import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/session_timezone.dart';

void main() {
  test('sessietijd wordt in de sessiezone weergegeven', () {
    // 08:00 UTC in oktober = 10:00 in Amsterdam (CEST).
    final view = sessionClockView(
      DateTime.utc(2026, 10, 2, 8),
      DateTime.utc(2026, 10, 2, 10),
      'Europe/Amsterdam',
    );
    expect(view.zoneKnown, isTrue);
    expect(view.sessionStart.hour, 10);
    expect(view.sessionEnd.hour, 12);
    expect(view.sessionStart.day, 2);
  });

  test('zomertijd/wintertijd-overgang volgt de tzdb', () {
    // Januari: CET = UTC+1.
    final view = sessionClockView(
      DateTime.utc(2026, 1, 15, 8),
      DateTime.utc(2026, 1, 15, 10),
      'Europe/Amsterdam',
    );
    expect(view.sessionStart.hour, 9);
  });

  test('een onbekende zone valt terug op de eigen tijd', () {
    final view = sessionClockView(
      DateTime.utc(2026, 10, 2, 8),
      DateTime.utc(2026, 10, 2, 10),
      'Mars/Olympus',
    );
    expect(view.zoneKnown, isFalse);
    expect(view.sameZone, isTrue);
  });

  test('de eigen klok is altijd de lokale vertaling van het moment', () {
    final start = DateTime.utc(2026, 10, 2, 8);
    final view = sessionClockView(start, DateTime.utc(2026, 10, 2, 10), 'UTC');
    expect(view.zoneKnown, isTrue);
    expect(view.localStart, start.toLocal());
    // Op deze machine (Europe/Amsterdam) wijkt UTC af van de eigen klok.
    expect(view.sameZone, start.toLocal().hour == 8);
  });
}
