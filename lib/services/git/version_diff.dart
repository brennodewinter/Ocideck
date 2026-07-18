import '../../models/deck.dart';
import '../../models/slide.dart';
import '../slide_dedup_service.dart';

/// Wat er met één slide gebeurde tussen twee uitgebrachte versies (§9.5).
enum SlideChangeKind {
  /// Identiek, en op dezelfde plek.
  unchanged,

  /// Identiek, maar verschoven naar een andere plek in het deck.
  moved,

  /// Herkenbaar dezelfde slide, met gewijzigde inhoud.
  edited,

  /// Alleen in de nieuwere versie.
  added,

  /// Alleen in de oudere versie.
  removed,
}

/// Eén regel in de vergelijking van twee versies.
///
/// [before]/[after] zijn de slide zoals hij in de oudere respectievelijk
/// nieuwere versie stond; bij [SlideChangeKind.added] is er geen `before` en bij
/// [SlideChangeKind.removed] geen `after`. De indices zijn 0-gebaseerd binnen hun
/// eigen versie, zodat de UI "slide 3 → slide 5" kan tonen.
class SlideChange {
  final SlideChangeKind kind;
  final Slide? before;
  final Slide? after;
  final int? beforeIndex;
  final int? afterIndex;

  /// De velden die verschillen, alleen gevuld bij [SlideChangeKind.edited].
  final List<SlideFieldDiff> fields;

  const SlideChange({
    required this.kind,
    this.before,
    this.after,
    this.beforeIndex,
    this.afterIndex,
    this.fields = const [],
  });
}

/// De uitkomst van het vergelijken van twee versies van hetzelfde deck.
class VersionDiff {
  /// De wijzigingen, op volgorde van de nieuwere versie; verwijderde slides
  /// staan op de plek waar ze stonden.
  final List<SlideChange> changes;

  const VersionDiff(this.changes);

  int _count(SlideChangeKind kind) =>
      changes.where((c) => c.kind == kind).length;

  int get addedCount => _count(SlideChangeKind.added);
  int get removedCount => _count(SlideChangeKind.removed);
  int get editedCount => _count(SlideChangeKind.edited);
  int get movedCount => _count(SlideChangeKind.moved);

  /// Of er iets veranderd is tussen de twee versies.
  bool get hasChanges =>
      addedCount + removedCount + editedCount + movedCount > 0;
}

/// Vergelijk twee versies van een deck op slide-niveau (§9.5).
///
/// De koppeling gebeurt in twee slagen, want een deck heeft geen slide-id's:
/// eerst op inhoudshandtekening (identieke slides vinden elkaar, ook als ze
/// verschoven zijn), daarna op gelijkenis binnen hetzelfde slidetype (zo wordt
/// een bijgewerkte slide herkend als *dezelfde* slide in plaats van als een
/// toevoeging plus een verwijdering). Wat daarna overblijft is echt toegevoegd
/// of verwijderd.
///
/// De koppeling is greedy en voorspelbaar: bij gelijke handtekening wint de
/// dichtstbijzijnde index, bij gelijkenis de hoogste score. Dat is genoeg voor
/// een leesbare vergelijking; een optimale alignment is hier de moeite niet.
VersionDiff diffDeckVersions(
  Deck before,
  Deck after, {
  SlideDedupService? dedup,
  double editedThreshold = 0.6,
}) {
  final service = dedup ?? SlideDedupService();
  final a = before.slides, b = after.slides;
  final matchedA = List<bool>.filled(a.length, false);
  // Voor elke slide in de nieuwe versie: de index in de oude, of null.
  final partner = List<int?>.filled(b.length, null);
  final editedFields = List<List<SlideFieldDiff>?>.filled(b.length, null);

  // Slag 1 — identieke inhoud. Bij meerdere kandidaten wint de dichtstbijzijnde
  // index, zodat een deck met herhaalde slides niet gaat kruislings koppelen.
  final sigA = [for (final s in a) service.signatureOf(s)];
  final sigB = [for (final s in b) service.signatureOf(s)];
  for (var j = 0; j < b.length; j++) {
    int? best;
    for (var i = 0; i < a.length; i++) {
      if (matchedA[i] || sigA[i] != sigB[j]) continue;
      if (best == null || (i - j).abs() < (best - j).abs()) best = i;
    }
    if (best != null) {
      matchedA[best] = true;
      partner[j] = best;
    }
  }

  // Slag 2 — gelijkende slides van hetzelfde type: bijgewerkt, niet vervangen.
  for (var j = 0; j < b.length; j++) {
    if (partner[j] != null) continue;
    int? best;
    var bestScore = editedThreshold;
    for (var i = 0; i < a.length; i++) {
      if (matchedA[i]) continue;
      final score = service.similarity(a[i], b[j]);
      if (score >= bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (best != null) {
      matchedA[best] = true;
      partner[j] = best;
      editedFields[j] = service.diff(a[best], b[j]);
    }
  }

  // Bouw de lijst op volgorde van de nieuwe versie; verwijderde slides schuiven
  // in op de plek waar ze in de oude versie stonden.
  final changes = <SlideChange>[];
  var nextA = 0;
  void flushRemovedBefore(int limit) {
    while (nextA < limit) {
      if (!matchedA[nextA]) {
        changes.add(
          SlideChange(
            kind: SlideChangeKind.removed,
            before: a[nextA],
            beforeIndex: nextA,
          ),
        );
      }
      nextA++;
    }
  }

  for (var j = 0; j < b.length; j++) {
    final i = partner[j];
    if (i == null) {
      changes.add(
        SlideChange(kind: SlideChangeKind.added, after: b[j], afterIndex: j),
      );
      continue;
    }
    flushRemovedBefore(i);
    if (nextA == i) nextA++;
    final fields = editedFields[j];
    changes.add(
      SlideChange(
        kind: fields != null
            ? SlideChangeKind.edited
            : (i == j ? SlideChangeKind.unchanged : SlideChangeKind.moved),
        before: a[i],
        after: b[j],
        beforeIndex: i,
        afterIndex: j,
        fields: fields ?? const [],
      ),
    );
  }
  flushRemovedBefore(a.length);

  return VersionDiff(changes);
}
