import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

/// De handelingen van de werkruimte, beschikbaar buiten de werkruimte zelf.
///
/// Bestaat voor de menubalk. Die hangt boven de hele app — ook boven het
/// openscherm, want een menubalk die verschijnt en verdwijnt is geen menubalk —
/// terwijl presenteren, exporteren, ongedaan maken en het commandopalet in de
/// editorlaag wonen en daar privé zijn. Deze klasse is de doorgeefluik: de
/// werkruimte publiceert wat ze kan zodra ze er is, en haalt het weg als ze
/// sluit. Staat er niets, dan zijn de menu-items uitgeschakeld in plaats van
/// afwezig — zo blijft zichtbaar wát de app kan, ook zonder open presentatie.
@immutable
class ShellDeckCommands {
  final VoidCallback present;
  final VoidCallback export;
  final VoidCallback save;
  final VoidCallback find;
  final VoidCallback findReplace;
  final VoidCallback properties;
  final VoidCallback commandPalette;
  final VoidCallback fullDeckPreview;
  final VoidCallback undo;
  final VoidCallback redo;

  /// Of de bijbehorende handeling nu iets kan doen. De menubalk grijst uit in
  /// plaats van te verbergen: een item dat komt en gaat, leert niemand wat de
  /// app kan.
  final bool canExport;
  final bool canUndo;
  final bool canRedo;

  const ShellDeckCommands({
    required this.present,
    required this.export,
    required this.save,
    required this.find,
    required this.findReplace,
    required this.properties,
    required this.commandPalette,
    required this.fullDeckPreview,
    required this.undo,
    required this.redo,
    required this.canExport,
    required this.canUndo,
    required this.canRedo,
  });

  /// Of alleen de aan/uit-standen verschillen. De werkruimte bouwt elke frame
  /// nieuwe closures; die opnieuw publiceren zou de menubalk elke frame laten
  /// herbouwen. De closures sluiten om de langlevende `State` heen, dus een
  /// oudere set blijft geldig — alleen een gewijzigde stand hoort door.
  bool sameEnablement(ShellDeckCommands other) =>
      canExport == other.canExport &&
      canUndo == other.canUndo &&
      canRedo == other.canRedo;
}

/// De gepubliceerde werkruimte-handelingen, of `null` zolang er geen
/// presentatie open is.
final shellDeckCommandsProvider = StateProvider<ShellDeckCommands?>(
  (_) => null,
);
