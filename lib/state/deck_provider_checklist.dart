part of 'deck_provider.dart';

/// `part of` extension for checklist deck actions — generating a checklist per
/// scope object (feedback #8) and resetting checkbox-bullet checklists — kept
/// out of the main notifier for the file-size ratchet. As an extension in the
/// same library it keeps access to `_mutate` and the deck state.
extension DeckNotifierChecklist on DeckNotifier {
  /// Generate one checklist slide per scope-matrix object that does not yet have
  /// one (feedback #8, "per scope-object heb je een checklist"). A `Web`/`API`
  /// object (standard = WSTG) is pre-filled with the full bundled WSTG list; any
  /// other type is pre-filled from [templateForOthers] when given (feedback #9),
  /// otherwise an empty checklist titled with its derived standard. Objects
  /// already linked to a checklist (by [Slide.checklistScope]) are skipped, so it
  /// is safe to re-run. Returns the number of checklists added, appended after
  /// the existing slides.
  int generateScopeChecklists({ChecklistTemplate? templateForOthers}) {
    final deck = currentState.deck;
    if (deck == null) return 0;
    final covered = <String>{
      for (final s in deck.slides)
        if (s.type == SlideType.checklist && s.checklistScope.trim().isNotEmpty)
          normalizeScopeObject(s.checklistScope),
    };
    final additions = <Slide>[];
    final seen = <String>{};
    for (final row in deckScopeRows(deck.slides)) {
      final object = row.object.trim();
      if (object.isEmpty) continue;
      final key = normalizeScopeObject(object);
      if (covered.contains(key) || !seen.add(key)) continue;
      additions.add(_checklistForScope(object, row.type, templateForOthers));
    }
    if (additions.isEmpty) return 0;
    final slides = List<Slide>.from(deck.slides)..addAll(additions);
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
    return additions.length;
  }

  /// Build a checklist slide linked to [object]: WSTG rows for a WSTG-standard
  /// type, [template] rows when one is given for a non-WSTG type, otherwise an
  /// empty checklist titled with the derived standard.
  /// Vink in één keer alle checklist-items in de hele presentatie uit (bijv.
  /// om een ingevulde checklist opnieuw te kunnen aflopen). Eén
  /// ongedaan-maken-stap. No-op wanneer er niets is aangevinkt.
  void clearAllChecklists() {
    final deck = currentState.deck;
    if (deck == null) return;
    String uncheck(String bullet) => checklistItemChecked(bullet)
        ? checklistBullet(
            level: bulletLevel(bullet),
            text: checklistItemText(bullet),
            checked: false,
          )
        : bullet;
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.bullets.any(checklistItemChecked) ||
          s.bullets2.any(checklistItemChecked)) {
        changed = true;
        slides.add(
          s.copyWith(
            bullets: [for (final b in s.bullets) uncheck(b)],
            bullets2: [for (final b in s.bullets2) uncheck(b)],
          ),
        );
      } else {
        slides.add(s);
      }
    }
    // Bump de revisie zodat de editor van de geselecteerde slide remount en de
    // uitgevinkte checkboxen ook in het invoerpaneel toont (niet alleen in de
    // slidepreview).
    if (changed) {
      _mutate(deck.copyWith(slides: slides), bumpRevision: true);
    }
  }

  /// Actively write a finding↔test link into the checklists (feedback #8):
  /// clears [findingId] from every checklist row that currently carries it, then
  /// — when [testId] is non-empty — sets it on the row with that id in the
  /// checklist that covers [scopeObject], marking that row an anomaly. Passing an
  /// empty [testId] therefore just unlinks. Status is only *raised* to anomaly on
  /// a match; unlinking leaves the row's status untouched (a tester may have set
  /// it deliberately). Returns whether a target row was found. One undo step.
  bool linkFindingToTest({
    required String findingId,
    required String scopeObject,
    required String testId,
  }) {
    final deck = currentState.deck;
    if (deck == null || findingId.isEmpty) return false;
    final scopeKey = normalizeScopeObject(scopeObject);
    final target = testId.trim().toUpperCase();
    var found = false;
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.type != SlideType.checklist) {
        slides.add(s);
        continue;
      }
      final spec = ChecklistSpec.fromSlide(s.title, s.tableRows);
      final inScope = normalizeScopeObject(s.checklistScope) == scopeKey;
      var rowsChanged = false;
      final rows = <ChecklistRow>[];
      for (final r in spec.rows) {
        if (inScope &&
            target.isNotEmpty &&
            r.id.trim().toUpperCase() == target) {
          found = true;
          rowsChanged = true;
          rows.add(
            r.copyWith(findingId: findingId, status: ChecklistStatus.anomaly),
          );
        } else if (r.findingId == findingId) {
          // Stale link on another row (or an unlink): clear it, keep the status.
          rowsChanged = true;
          rows.add(r.copyWith(findingId: ''));
        } else {
          rows.add(r);
        }
      }
      if (rowsChanged) {
        changed = true;
        slides.add(
          s.copyWith(
            tableRows: ChecklistSpec(
              standardLabel: spec.standardLabel,
              rows: rows,
            ).toTableRows(),
          ),
        );
      } else {
        slides.add(s);
      }
    }
    if (changed) _mutate(deck.copyWith(slides: slides), bumpRevision: true);
    return found;
  }
}

/// De checklist-dia voor één scope-object.
///
/// Top-level en geen methode: hij raakt geen enkel veld van [DeckNotifier],
/// en die klasse zit tegen zijn plafond (#630). Wat hij nodig heeft komt
/// allemaal binnen via zijn parameters — dit was een pure functie die per
/// ongeluk een methode werd.
Slide _checklistForScope(
  String object,
  ScopeObjectType type,
  ChecklistTemplate? template,
) {
  final ChecklistSource source;
  if (type.standard == 'WSTG') {
    source = wstgChecklistSource();
  } else if (template != null) {
    source = templateChecklistSource(template);
  } else {
    source = ChecklistSource(
      label: type.standard,
      standardLabel: type.standard,
      rows: const [ChecklistRow()],
    );
  }
  final label = source.standardLabel.isNotEmpty
      ? source.standardLabel
      : type.standard;
  return Slide.create(SlideType.checklist).copyWith(
    title: label,
    tableRows: ChecklistSpec(
      standardLabel: label,
      rows: source.rows,
    ).toTableRows(),
    checklistScope: object,
  );
}
