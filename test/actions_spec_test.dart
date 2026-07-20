import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/actions_spec.dart';

ActionsSpec _parse(List<List<String>> rows) =>
    ActionsSpec.fromSlide('Wat we vragen', rows);

final _asOf = DateTime(2026, 7, 20);

void main() {
  group('ActionItem.isOverdue', () {
    test('a passed deadline on an open action is overdue', () {
      final late = ActionItem(action: 'X', due: DateTime(2026, 7, 19));
      expect(late.isOverdue(_asOf), isTrue);
    });

    test('the deadline day itself is not yet overdue', () {
      final today = ActionItem(action: 'X', due: DateTime(2026, 7, 20));
      expect(today.isOverdue(_asOf), isFalse);
    });

    test('the time of day never decides it', () {
      // Same calendar day, later clock time — still not overdue.
      final item = ActionItem(action: 'X', due: DateTime(2026, 7, 20));
      expect(item.isOverdue(DateTime(2026, 7, 20, 23, 59)), isFalse);
      expect(item.isOverdue(DateTime(2026, 7, 21, 0, 1)), isTrue);
    });

    test('a finished action is never overdue, however late it was', () {
      final done = ActionItem(
        action: 'X',
        due: DateTime(2026, 1, 1),
        status: ActionStatus.done,
      );
      // The slide reports where things stand, not how they got there.
      expect(done.isOverdue(_asOf), isFalse);
    });

    test('an action without a deadline cannot be late', () {
      const undated = ActionItem(action: 'X');
      expect(undated.isOverdue(_asOf), isFalse);
    });

    test('an in-progress action is still overdue past its date', () {
      final running = ActionItem(
        action: 'X',
        due: DateTime(2026, 6, 1),
        status: ActionStatus.inProgress,
      );
      expect(running.isOverdue(_asOf), isTrue);
    });
  });

  group('ActionsSpec counts', () {
    test('asks are counted, reports are not', () {
      const spec = ActionsSpec(
        items: [
          ActionItem(action: 'A', kind: ActionKind.info),
          ActionItem(action: 'B', kind: ActionKind.decision),
          ActionItem(action: 'C', kind: ActionKind.escalation),
        ],
      );
      expect(spec.askCount, 2);
    });

    test('overdue is counted against the given date', () {
      final spec = ActionsSpec(
        items: [
          ActionItem(action: 'A', due: DateTime(2026, 1, 1)),
          ActionItem(action: 'B', due: DateTime(2027, 1, 1)),
          ActionItem(
            action: 'C',
            due: DateTime(2026, 1, 1),
            status: ActionStatus.done,
          ),
        ],
      );
      expect(spec.overdueCount(_asOf), 1);
      // Wind the clock forward and the same deck says something different.
      expect(spec.overdueCount(DateTime(2028, 1, 1)), 2);
    });
  });

  group('ActionsSpec round-trip', () {
    test('toTableRows/fromSlide is a fixed point', () {
      final spec = ActionsSpec(
        title: 'Wat we vragen',
        items: [
          ActionItem(
            action: 'acc-oud.example uit de lucht halen',
            owner: 'Team Platform',
            due: DateTime(2026, 8, 15),
            since: DateTime(2026, 5, 12),
            status: ActionStatus.open,
            kind: ActionKind.decision,
          ),
        ],
      );
      final again = _parse(spec.toTableRows());
      final item = again.items.single;
      expect(item.action, 'acc-oud.example uit de lucht halen');
      expect(item.owner, 'Team Platform');
      expect(item.due, DateTime(2026, 8, 15));
      expect(item.since, DateTime(2026, 5, 12));
      expect(item.status, ActionStatus.open);
      expect(item.kind, ActionKind.decision);
      expect(again.toTableRows(), spec.toTableRows());
    });

    test('dates are written as ISO', () {
      final spec = ActionsSpec(
        items: [ActionItem(action: 'X', due: DateTime(2026, 8, 5))],
      );
      expect(spec.toTableRows()[1][2], '2026-08-05');
    });

    test('an absent date stays an empty cell', () {
      const spec = ActionsSpec(items: [ActionItem(action: 'X')]);
      expect(spec.toTableRows()[1][2], '');
      expect(spec.toTableRows()[1][5], '');
      expect(_parse(spec.toTableRows()).items.single.due, isNull);
    });

    test('a blank row never reaches the table on write either', () {
      const spec = ActionsSpec(
        items: [ActionItem(action: 'X'), ActionItem()],
      );
      expect(spec.toTableRows().length, 2);
      expect(_parse(spec.toTableRows()).items.length, 1);
    });
  });

  group('ActionsSpec tolerant parse', () {
    test('the header row is skipped', () {
      final spec = _parse([
        ActionsSpec.header,
        ['Iets doen', 'Infra', '2026-08-01', 'open', 'decision', ''],
      ]);
      expect(spec.items.single.action, 'Iets doen');
    });

    test('an unreadable date costs the date, not the row', () {
      final spec = _parse([
        ActionsSpec.header,
        ['Iets doen', 'Infra', 'volgende maand', 'open', 'decision', ''],
      ]);
      expect(spec.items.single.action, 'Iets doen');
      expect(spec.items.single.due, isNull);
      expect(spec.items.single.kind, ActionKind.decision);
    });

    test('an unknown status or kind falls back to the quietest value', () {
      final spec = _parse([
        ActionsSpec.header,
        ['Iets doen', '', '', 'bijna-klaar', 'heel-dringend', ''],
      ]);
      // Understating an ask is recoverable; inventing one is not.
      expect(spec.items.single.status, ActionStatus.open);
      expect(spec.items.single.kind, ActionKind.info);
    });

    test('short rows read as absent cells, not as an error', () {
      final spec = _parse([
        ['Iets doen', 'Infra'],
      ]);
      expect(spec.items.single.owner, 'Infra');
      expect(spec.items.single.due, isNull);
      expect(spec.items.single.status, ActionStatus.open);
    });

    test('an owner alone is enough to keep the row', () {
      final spec = _parse([
        ActionsSpec.header,
        ['', 'Infra', '', '', '', ''],
        ['', '', '', '', '', ''],
      ]);
      expect(spec.items.length, 1);
      expect(spec.items.single.owner, 'Infra');
    });

    test('more items than fit are capped on read', () {
      final spec = _parse([
        ActionsSpec.header,
        for (var i = 0; i < actionsMaxItems + 3; i++) ['A$i'],
      ]);
      expect(spec.items.length, actionsMaxItems);
    });
  });

  group('parseActionDate', () {
    test('reads an ISO date', () {
      expect(parseActionDate(' 2026-08-15 '), DateTime(2026, 8, 15));
    });

    test('refuses an ambiguous form rather than guessing', () {
      // 05-08-2026 is two different days depending on who typed it, and a
      // deadline is a bad place to be wrong by three months.
      expect(parseActionDate('05-08-2026'), isNull);
      expect(parseActionDate('15/08/2026'), isNull);
      expect(parseActionDate('morgen'), isNull);
      expect(parseActionDate(''), isNull);
    });

    test('refuses a date the calendar does not have', () {
      expect(parseActionDate('2026-02-31'), isNull);
      expect(parseActionDate('2026-13-01'), isNull);
      expect(parseActionDate('2026-00-10'), isNull);
    });
  });

  test('formatActionDate pads to ISO and blanks a null', () {
    expect(formatActionDate(DateTime(2026, 8, 5)), '2026-08-05');
    expect(formatActionDate(null), '');
  });

  test('every kind and status has a Dutch source label', () {
    for (final kind in ActionKind.values) {
      expect(actionKindDutchLabel(kind), isNotEmpty);
    }
    for (final status in ActionStatus.values) {
      expect(actionStatusDutchLabel(status), isNotEmpty);
    }
  });
}
