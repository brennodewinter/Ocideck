import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:path/path.dart' as p;

import '../../test/support/pump_until.dart';

const _unsavedText = 'Unsaved native recovery text.';
const _offer = 'Niet-opgeslagen werk herstellen?';

Future<Map<String, Object?>> runNativeRecoveryScenario(
  WidgetTester tester,
  ProviderContainer container,
  String root,
  String support,
  String phase,
) async {
  final tabs = container.read(tabsProvider.notifier);
  final recovery = Directory(p.join(support, 'recovery'));
  List<File> snapshots() => !recovery.existsSync()
      ? []
      : recovery
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList();

  if (phase == 'document-crash') {
    tabs.newDocumentFromMarkdown('# Native recovery\n\nBefore the crash.');
    await tester.pumpAndSettle();
    final editor = tester.widget<WysiwygNotesField>(
      find.byType(WysiwygNotesField),
    );
    editor.controller.replaceText(
      0,
      0,
      '$_unsavedText ',
      const TextSelection.collapsed(offset: 0),
    );
    await pumpUntil(
      tester,
      () => snapshots().any(
        (file) => file.readAsStringSync().contains(_unsavedText),
      ),
      timeout: const Duration(seconds: 20),
      reason: 'The production visual-edit autosave must reach disk',
    );
    expect(snapshots(), hasLength(1));
    return {'snapshot_written': true};
  }

  if (phase == 'early-crash') {
    expect(
      await tabs.openFileByPath(p.join(root, 'journey.md')),
      OpenResult.opened,
    );
    final deck = container.read(tabsProvider).current!.deckNotifier;
    final slide = deck.currentState.deck!.slides.first;
    deck.updateSlide(0, slide.copyWith(title: _unsavedText));
    expect(deck.currentState.isDirty, isTrue);
    expect(snapshots(), isEmpty);
    return {'snapshot_written': false};
  }

  final log = File(p.join(support, 'logs', 'journey-recovery.log'));
  expect(log.readAsStringSync(), contains('is niet netjes afgesloten'));
  final offer = find.text(_offer);
  if (phase == 'early-reopen') {
    await tester.pumpAndSettle();
    expect(offer, findsNothing);
    expect(snapshots(), isEmpty);
    return {'unclean_exit_detected': true, 'offered_recovery': false};
  }

  await pumpUntil(
    tester,
    () => offer.evaluate().isNotEmpty,
    reason: 'The startup shell must offer the saved document',
  );
  await tester.tap(find.text('Openen en verder werken'));
  await tester.pumpAndSettle();
  final state = container.read(tabsProvider);
  final notifier = state.current!.documentNotifier!;
  expect(notifier.currentState.document!.source, contains(_unsavedText));
  expect(notifier.currentState.isDirty, isTrue);
  tabs.closeTab(state.selectedIndex);
  await tester.pumpAndSettle();
  return {
    'unclean_exit_detected': true,
    'offered_recovery': true,
    'recovered_text': true,
  };
}
