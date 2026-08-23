import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

/// De import schrijft twee soorten Nederlandse tekst naar de gebruiker die de
/// gewone vertaalpoort niet ziet (#806):
///
///  1. **Notitiedia's** — de "niet overgenomen"-tekst die als *inhoud* in het
///     `.md` van de gebruiker belandt en daar blijft staan, ook nadat hij de
///     app op een andere taal zet. Die wordt op importmoment vertaald en zó
///     opgeslagen, via de `translate`-naad in `UnconvertedTracker`/`DeckBuilder`.
///  2. **Vaste voortgangsteksten** — "Formaat herkennen…", "Deck opbouwen…" —
///     die de wachtrijdialoog via `l10n.d(progress.message)` toont.
///
/// Beide reizen als een kale bronstring door de servicelaag (die geen
/// `BuildContext` heeft), niet als een letterlijke `d('…')`. Daardoor pakt noch
/// de regex-toets noch de datastroomanalyse van `app_localizations_test` ze op —
/// en zonder deze poort zou een Griekse gebruiker permanent Nederlandse alinea's
/// in zijn bestand houden, onopgemerkt.
///
/// Deze poort haalt de strings via de AST uit de bron en eist dat elk in alle
/// 31 talen bestaat. Zo dwingt hij niet alleen de vertaling af, maar ook dat een
/// **nieuwe** notitie- of voortgangsstring niet stilletjes onvertaald ontsnapt.
void main() {
  test(
    'elke import-notitie en vaste voortgangstekst is in elke taal vertaald',
    () {
      final sources = _importNoteSources('lib/services/import');

      // Een stilgevallen extractie meldt niets en zou dus groen zijn — dat is de
      // ene manier waarop deze test kan liegen.
      expect(
        sources.length,
        greaterThan(30),
        reason:
            'De extractie vond opvallend weinig bronstrings; klopt de AST-scan '
            'nog met de vorm van de ConversionIssue-constructies?',
      );

      final missingByLanguage = <String, List<String>>{};
      for (final languageCode in AppLocalizations.languageNames.keys) {
        if (languageCode == 'nl') continue;
        final missing = sources.where((source) {
          return !AppLocalizations.hasDirectDutchSourceTranslation(
            languageCode,
            source,
          );
        }).toList()..sort();
        if (missing.isNotEmpty) missingByLanguage[languageCode] = missing;
      }

      expect(
        missingByLanguage,
        isEmpty,
        reason:
            'Deze import-notities/voortgangsteksten belanden onvertaald bij de '
            'gebruiker. Voeg ze toe met `make add-l10n` (spec met alle 31 '
            'talen).',
      );
    },
  );
}

/// Alle Nederlandse bronstrings die de import als inhoud of vaste voortgang naar
/// de gebruiker schrijft, via de AST van de servicelaag. Drie bronnen:
///
///  1. `feature:`/`description:`/`salvagedAs:` van elke `ConversionIssue`
///     (ook wanneer de waarde een ternary is: beide takken tellen).
///  2. `translate('…')` — de koppen en labels die de tracker/bouwer vertaalt.
///  3. `onProgress?.call(x, '…')` / `report(x, '…')` / `ImportProgress(x, '…')`
///     — de voortgangsteksten, sinds #875 ook als contractobject.
///
/// `StringLiteral.stringValue` doet het zware werk goed: aangrenzende literals
/// worden samengevoegd tot de string die `l10n.d` bij runtime krijgt, en een
/// string met een rauwe `$`-interpolatie levert `null` — precies wat we willen
/// overslaan, want die is per taal onvindbaar. De notitiestrings gebruiken
/// daarom `{naam}`-plaatshouders; de enige `$`-uitzonderingen zijn de per-dia
/// voortgangsregels ("Slide 3/10"), vluchtig en vrijwel geheel numeriek.
Set<String> _importNoteSources(String root) {
  final found = <String>{};
  final files = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final unit = parseFile(
      // `parseFile` eist een genormaliseerd pad. De hardgecodeerde root gebruikt
      // `/`, maar `listSync` hangt op Windows de bestandsnaam met `\` aan —
      // dat gemengde pad wijst de analyzer af. `p.normalize` maakt er één
      // consistente scheiding van (#926).
      path: p.normalize(file.absolute.path),
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    unit.accept(_NoteVisitor(found));
  }
  return found;
}

class _NoteVisitor extends RecursiveAstVisitor<void> {
  _NoteVisitor(this.found);

  final Set<String> found;
  static const _noteArgs = {'feature', 'description', 'salvagedAs'};
  static const _progressCallees = {'call', 'report'};

  /// Voegt elke string-literal binnen [node] toe (beide takken van een ternary,
  /// aangrenzende literals samengevoegd); een geïnterpoleerde string levert
  /// `null` en valt af.
  void _collect(AstNode? node) {
    if (node == null) return;
    for (final literal in _stringLiteralsIn(node)) {
      final value = literal.stringValue;
      if (value != null && value.isNotEmpty) found.add(value);
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (_noteArgs.contains(node.name.lexeme)) {
      _collect(node.argumentExpression);
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    // `translate('…')`: de koppen/labels die de tracker vertaalt.
    if (name == 'translate' && node.argumentList.arguments.isNotEmpty) {
      _collect(node.argumentList.arguments.first);
    }
    // `onProgress?.call(x, '…')` en `report(x, '…')`: de voortgangsteksten
    // staan op de tweede positie.
    if (_progressCallees.contains(name) &&
        node.argumentList.arguments.length >= 2) {
      _collect(node.argumentList.arguments[1]);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `ImportProgress(x, '…')`: sinds #875 dragen de voortgangsstappen hun
    // tekst als tweede positioneel argument van dit contractobject, in plaats
    // van via een losse `onProgress`-aanroep. De literal-varianten horen even
    // hard vertaald te zijn als de rest.
    if (node.constructorName.type.toSource() == 'ImportProgress' &&
        node.argumentList.arguments.length >= 2) {
      _collect(node.argumentList.arguments[1]);
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// Elke [StringLiteral] onder [node], inclusief die in de takken van een
/// conditional expression.
Iterable<StringLiteral> _stringLiteralsIn(AstNode node) {
  final collector = _StringLiteralCollector();
  node.accept(collector);
  return collector.literals;
}

class _StringLiteralCollector extends RecursiveAstVisitor<void> {
  final literals = <StringLiteral>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    literals.add(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    // De hele aangrenzende reeks is één sleutel; niet ook de losse stukken.
    literals.add(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    literals.add(node);
  }
}
