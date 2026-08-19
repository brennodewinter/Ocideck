import 'package:flutter/widgets.dart';

/// Geeft een tekstveld dat *binnen* een Quill-embed staat zijn eigen
/// tekstbewerking terug.
///
/// Een invulbare tabelcel of notenregel leeft in een embed, en dus in de
/// widgetboom ónder de Quill-editor. Een [EditableText] laat zijn
/// tekstbewerkingsacties bewust overschrijven door een [Actions] hoger in de
/// boom ([Action.overridable]) — en Quill zet die daar. Gevolg: één pijltje in
/// een cel liet Quill de cursor van het *document* verzetten en dat resultaat
/// vervolgens ín de cel schrijven. De hele documenttekst belandde in één cel,
/// de bron kreeg er `<br>`-tekens bij en de visuele stand viel op brontekst
/// terug (#1565).
///
/// Deze wikkel zet dezelfde acties nóg een keer, maar dichterbij: het veld
/// vindt eerst deze doorgeefacties en die roepen de eigen standaardactie van
/// het veld aan ([Action.callingAction]). Quill komt er niet meer aan te pas,
/// en het veld beweegt, selecteert, wist en plakt weer in zichzelf.
class EmbeddedFieldActions extends StatefulWidget {
  const EmbeddedFieldActions({super.key, required this.child});

  final Widget child;

  @override
  State<EmbeddedFieldActions> createState() => _EmbeddedFieldActionsState();
}

class _EmbeddedFieldActionsState extends State<EmbeddedFieldActions> {
  /// Eén keer gemaakt en niet per opbouw: een actie houdt tijdens het uitvoeren
  /// bij welke actie hij overschrijft, en dat mag niet onder hem vandaan
  /// vervangen worden.
  late final Map<Type, Action<Intent>> _actions = _passThroughActions();

  @override
  Widget build(BuildContext context) =>
      Actions(actions: _actions, child: widget.child);
}

/// Elke actie die [EditableText] overschrijfbaar maakt én die Quill in zijn
/// eigen [Actions] zet. Wat hier niet in staat, blijft van Quill — dat is
/// terecht voor alles wat over het *document* gaat en niet over dit veld.
Map<Type, Action<Intent>> _passThroughActions() => <Type, Action<Intent>>{
  for (final intent in const <Type>[
    DeleteCharacterIntent,
    DeleteToNextWordBoundaryIntent,
    DeleteToLineBreakIntent,
    ExtendSelectionByCharacterIntent,
    ExtendSelectionToNextWordBoundaryIntent,
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent,
    ExtendSelectionToLineBreakIntent,
    ExtendSelectionVerticallyToAdjacentLineIntent,
    ExtendSelectionVerticallyToAdjacentPageIntent,
    ExtendSelectionToDocumentBoundaryIntent,
    ExpandSelectionToLineBreakIntent,
    ExpandSelectionToDocumentBoundaryIntent,
    ScrollToDocumentBoundaryIntent,
    SelectAllTextIntent,
    CopySelectionTextIntent,
    PasteTextIntent,
  ])
    intent: _OwnBehaviour(),
};

/// Doet precies wat het veld zelf zou doen: hij roept de standaardactie aan die
/// hij overschrijft. Zo is dit geen nieuw gedrag maar een afscherming.
///
/// Bewust niet generiek op het bedoelingstype: de standaardactie van een veld
/// staat soms op een *ruimer* type geschreven (één actie voor de regel omhoog
/// én de bladzijde omhoog), en dan struikelt de getypeerde [callingAction] over
/// zijn eigen omzetting.
class _OwnBehaviour extends Action<Intent> {
  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? false;

  @override
  bool isEnabled(Intent intent) => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(Intent intent) => callingAction?.consumesKey(intent) ?? true;

  @override
  Object? invoke(Intent intent) => callingAction?.invoke(intent);
}
