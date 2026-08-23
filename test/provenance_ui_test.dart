import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/provenance_signature.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/provenance_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  AppLocalizations l10n() => const AppLocalizations(Locale('nl'));

  ProvenanceOutcome outcome(ProvenanceStatus s) =>
      ProvenanceOutcome(s, 'AAAA BBBB');

  group('provenanceBadgeVisual', () {
    test('no signature → no badge', () {
      expect(
        provenanceBadgeVisual(outcome(ProvenanceStatus.none), l10n()),
        isNull,
      );
    });

    test('each meaningful status maps to a distinct label', () {
      final labels = {
        for (final s in [
          ProvenanceStatus.confirmed,
          ProvenanceStatus.valid,
          ProvenanceStatus.contentChanged,
          ProvenanceStatus.invalid,
          ProvenanceStatus.notVerifiableHere,
        ])
          s: provenanceBadgeVisual(outcome(s), l10n())!.label,
      };
      // All present and distinct.
      expect(labels.values.toSet().length, labels.length);
      expect(labels[ProvenanceStatus.confirmed], 'Herkomst bevestigd');
      expect(labels[ProvenanceStatus.valid], 'Ondertekend');
      expect(labels[ProvenanceStatus.invalid], 'Herkomst ongeldig');
    });

    test('the unpinned tooltip carries the fingerprint', () {
      final v = provenanceBadgeVisual(outcome(ProvenanceStatus.valid), l10n())!;
      expect(v.tooltip, contains('AAAA BBBB'));
    });
  });

  test('DeckNotifier.applyProvenance sets it and marks dirty', () {
    final md = MarkdownService();
    final notifier = DeckNotifier(
      md,
      FileService(md, ImageService(), () => const ThemeProfile()),
    )..loadDeck(Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]));
    const prov = ProvenanceSignature(
      alg: 'ed25519',
      preimage: 'ocideck-provenance-v1',
      identityKey: [1, 2, 3],
      signature: [4, 5, 6],
      signedAt: '2026-08-01T00:00:00.000Z',
    );
    notifier.applyProvenance(prov);
    expect(notifier.currentState.deck!.provenance, prov);
    expect(notifier.currentState.isDirty, isTrue);

    notifier.applyProvenance(null);
    expect(notifier.currentState.deck!.provenance, isNull);
  });
}
