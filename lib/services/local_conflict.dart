import '../models/deck.dart';
import '../models/slide.dart';
import 'git/deck_merge.dart';
import 'git/version_diff.dart';

/// De drie versies bij een lokaal bestandsconflict (#2323), met de
/// vergelijking en de driewegs-merge er al bij. Alles hier is puur — de
/// schil leest de schijfversie door de bestaande open-poorten en laat de
/// keuzes aan de gebruiker.
class LocalDeckConflict {
  /// De versie zoals die bij de laatste geslaagde open- of opslagbeurt op
  /// schijf stond; de gemeenschappelijke voorouder van [ours] en [theirs].
  /// Zonder bekende basis ([hasBase] false) is dit [ours] als plaatsaanduiding.
  final Deck base;

  /// Het niet-opgeslagen werk in het open tabblad.
  final Deck ours;

  /// Het bestand zoals het nú op schijf staat.
  final Deck theirs;

  /// Of [base] de echte laatst-bekende schijfversie is. Zonder die is er geen
  /// driewegs-merge mogelijk — de dialoog toont dan alleen het verschil.
  final bool hasBase;

  /// Wat wij ten opzichte van de basis deden (leeg zonder basis), en wat er
  /// verschilt aan de andere kant: de schijfversie tegen de basis, of — zonder
  /// basis — tegen onze versie. Beide zijn het overzicht dat de dialoog toont.
  final VersionDiff oursDiff;
  final VersionDiff theirsDiff;

  /// De driewegs-merge; [DeckMergeResult.isClean] zegt of er niets te
  /// kiezen valt. Bij conflicten staat voorlopig onze kant in `merged`.
  /// Null zonder betrouwbare basis.
  final DeckMergeResult? merge;

  const LocalDeckConflict({
    required this.base,
    required this.ours,
    required this.theirs,
    required this.hasBase,
    required this.oursDiff,
    required this.theirsDiff,
    required this.merge,
  });
}

/// Vergelijk en voeg de lokale versie en de schijfversie samen tegen de
/// gemeenschappelijke [base]. Hergebruikt de bewezen git-diff en -merge;
/// de enige nieuwe stap is de schil eromheen.
LocalDeckConflict analyzeLocalDeckConflict({
  required Deck? base,
  required Deck ours,
  required Deck theirs,
}) {
  return LocalDeckConflict(
    base: base ?? ours,
    ours: ours,
    theirs: theirs,
    hasBase: base != null,
    oursDiff: base == null
        ? const VersionDiff([])
        : diffDeckVersions(base, ours),
    theirsDiff: base == null
        ? diffDeckVersions(ours, theirs)
        : diffDeckVersions(base, theirs),
    merge: base == null ? null : mergeDeckVersions(base, ours, theirs),
  );
}

/// Pas de gekozen kant per slide-conflict toe op de merge-uitkomst.
///
/// [picks] heeft één waarde per conflict uit [DeckMergeResult.conflicts]:
/// de slide die blijft — meestal `ours` of `theirs` van dat conflict — of
/// `null` om hem weg te gooien (bij een verwijder-tegen-wijzig-botsing is
/// dat de "verwijderd houden"-kant). Wat al zonder conflict in de merge
/// zat blijft ongemoeid.
Deck applyDeckConflictChoices(DeckMergeResult merge, List<Slide?> picks) {
  assert(picks.length == merge.conflicts.length);
  final slides = [...merge.merged.slides];
  final remove = <int>[];
  for (var i = 0; i < merge.conflicts.length; i++) {
    final at = merge.conflicts[i].mergedIndex;
    if (at == null) continue;
    final pick = i < picks.length ? picks[i] : null;
    if (pick == null) {
      remove.add(at);
    } else {
      slides[at] = pick;
    }
  }
  // Van achter naar voren verwijderen zodat de indices kloppend blijven.
  for (final at in remove..sort((a, b) => b.compareTo(a))) {
    slides.removeAt(at);
  }
  return merge.merged.copyWith(slides: slides);
}

/// Eén uitgelijnde rij in de documentvergelijking: wat links en rechts op
/// die plek staat. `equal` zegt of beide zijden identiek zijn; bij een
/// toevoeging of verwijdering is één kant `null`.
class DocDiffPair {
  final String? ours;
  final String? theirs;
  final bool equal;

  const DocDiffPair(this.ours, this.theirs, this.equal);
}

/// Vergelijk twee documentbronnen per blok (alinea's, koppen, tabellen,
/// codeblokken — gescheiden door lege regels). De blokken worden met LCS
/// uitgelijnd, zodat een ingeschoven alinea zijn buren niet meetrekt.
///
/// Bewust géén tekstuele merge: de dialoog toont dit overzicht en de
/// gebruiker kiest een hele versie. Regels die de codec niet kent —
/// frontmatter, BOM, CRLF — kunnen hier niet verkeerd gaan omdat er niets
/// herschreven wordt.
List<DocDiffPair> diffDocBlocks(String ours, String theirs) {
  if (ours == theirs) return [DocDiffPair(ours, theirs, true)];
  final a = _splitBlocks(ours);
  final b = _splitBlocks(theirs);
  final lcs = _lcsTable(a, b);
  final pairs = <DocDiffPair>[];
  var i = a.length, j = b.length;
  // Achteruit langs de LCS-tabel: equal-blokken paren, de rest komt in
  // "verwijderd/toegevoegd"-rijen terecht.
  final reversed = <DocDiffPair>[];
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
      reversed.add(DocDiffPair(a[i - 1], b[j - 1], true));
      i--;
      j--;
    } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
      reversed.add(DocDiffPair(null, b[j - 1], false));
      j--;
    } else {
      reversed.add(DocDiffPair(a[i - 1], null, false));
      i--;
    }
  }
  // Aaneengesloten bewerkingen als vervang-paren naast elkaar tonen leest
  // beter dan een verwijderrij gevolgd door een toevoegrij.
  for (var k = reversed.length - 1; k >= 0; k--) {
    final cur = reversed[k];
    if (cur.ours == null &&
        pairs.isNotEmpty &&
        pairs.last.theirs == null &&
        !pairs.last.equal) {
      pairs[pairs.length - 1] = DocDiffPair(pairs.last.ours, cur.theirs, false);
    } else {
      pairs.add(cur);
    }
  }
  return pairs;
}

/// Woordniveau-markering binnen één veranderd blok, gezien vanaf [a]: elk
/// stukje tekst uit `a` met of `b` het op die plek ook kent. Roep de functie
/// andersom aan voor de markering van de andere kant.
List<({String text, bool changed})> diffDocWords(String a, String b) {
  final ta = _splitWords(a);
  final tb = _splitWords(b);
  final lcs = _lcsTable(ta, tb);
  final out = <({String text, bool changed})>[];
  var i = ta.length, j = tb.length;
  final reversed = <({String text, bool changed})>[];
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && ta[i - 1] == tb[j - 1]) {
      reversed.add((text: ta[i - 1], changed: false));
      i--;
      j--;
    } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
      // Een woord dat alleen `b` kent hoort niet in de weergave van `a`.
      j--;
    } else {
      reversed.add((text: ta[i - 1], changed: true));
      i--;
    }
  }
  for (var k = reversed.length - 1; k >= 0; k--) {
    final cur = reversed[k];
    if (out.isNotEmpty && out.last.changed == cur.changed) {
      out[out.length - 1] = (
        text: out.last.text + cur.text,
        changed: cur.changed,
      );
    } else {
      out.add(cur);
    }
  }
  return out;
}

/// Blokken: alinea's en constructies gescheiden door lege regels. De
/// scheiding zelf valt weg — dat maakt `\n` vs `\r\n` en
/// witruimte-verschillen onzichtbaar in plaats van een vals verschil.
List<String> _splitBlocks(String source) => source
    .split(RegExp(r'\r?\n[ \t]*\r?\n'))
    .map((b) => b.trim())
    .where((b) => b.isNotEmpty)
    .toList();

/// Woordtokens voor de markering: woorden en witruimte afzonderlijk, zodat
/// de markering alleen de gewijzigde woorden treft en niet hun spatie.
List<String> _splitWords(String text) =>
    RegExp(r'\s+|[^\s]+').allMatches(text).map((m) => m.group(0)!).toList();

/// De klassieke LCS-lengtetabel — klein genoeg voor documenten (blokken)
/// en losse alinea's (woorden).
List<List<int>> _lcsTable(List<String> a, List<String> b) {
  final t = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      t[i][j] = a[i - 1] == b[j - 1]
          ? t[i - 1][j - 1] + 1
          : (t[i - 1][j] > t[i][j - 1] ? t[i - 1][j] : t[i][j - 1]);
    }
  }
  return t;
}
