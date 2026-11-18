import 'package:flutter_test/flutter_test.dart';

import '../tool/async_progress_rules.dart';

void main() {
  test(
    'rasterexport mag geen onbegrensde afbeeldingsvoorlader terugkrijgen',
    () {
      const path = 'lib/services/slide_rasterizer.dart';
      expect(
        asyncProgressViolationsIn(
          'void f() => precacheImage(provider, context).timeout(timeout);',
          path: path,
        ),
        hasLength(1),
      );
      expect(
        asyncProgressViolationsIn(
          'void f() => preloadExportImage(provider, config, source: path);',
          path: path,
        ),
        isEmpty,
      );
    },
  );

  List<String> check(
    String source, {
    String path = 'lib/services/example.dart',
  }) => asyncProgressViolationsIn(source, path: path);

  test('idle, onbekende prioriteit en tear-offs worden geweigerd', () {
    expect(
      check('''
void f() async {
  await binding.scheduleTask<void>(() {}, Priority.idle);
  binding.scheduleTask(work, priority);
  binding.scheduleTask(work, s.Priority.idle + 1);
  final task = binding.scheduleTask;
}
'''),
      hasLength(4),
    );
  });

  test('expliciete animatieprioriteit en gewone event-loop-yields mogen', () {
    expect(
      check('''
void f() async {
  await binding.scheduleTask(work, Priority.animation);
  await binding.scheduleTask(work, s.Priority.touch);
  await Future<void>.delayed(Duration.zero);
  await waitForUiFrame();
}
'''),
      isEmpty,
    );
  });

  test('framewacht moet ook met lokale timeout via de gedeelde helper', () {
    expect(
      check('''
void f() async {
  await WidgetsBinding.instance.endOfFrame;
  await binding.endOfFrame.timeout(timeout);
}
'''),
      hasLength(2),
    );
    expect(
      check(
        'void f() => binding.endOfFrame.timeout(timeout);',
        path: 'lib/utils/ui_frame.dart',
      ),
      isEmpty,
    );
  });

  test('comments en bronvoorbeelden tellen niet als uitvoerbare code', () {
    expect(
      check('''
// await binding.scheduleTask(work, Priority.idle);
/// Zie [WidgetsBinding.endOfFrame] en [binding.scheduleTask].
const example = 'await binding.endOfFrame';
/* binding.scheduleTask(work, Priority.idle); */
'''),
      isEmpty,
    );
  });
}
