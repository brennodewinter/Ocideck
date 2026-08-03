// Stabiele dia-ankers voor de niet-lineaire navigatie (#1162).
//
// Een anker is het handvat waar een menublok of een sprong-uit naar wijst. Het
// wordt geseed uit de kop van de doeldia maar daarna bevroren opgeslagen, zodat
// hernoemen een bestaande link niet breekt. De gebruiker ziet het anker nooit;
// die kiest een doeldia visueel en de app kent er het anker aan toe.

import '../models/slide.dart';

/// Een ASCII-veilig anker uit [title]: kleine letters, koppeltekens tussen
/// woorden, alleen `a–z`/`0–9`. Niet-ASCII (bv. een kop in het Chinees) valt
/// weg — het anker is machinerie, geen zichtbare tekst — met `dia` als terugval
/// zodat er altijd iets bruikbaars overblijft om uniek te maken.
String slugifyAnchor(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'dia' : slug;
}

/// Maak [seed] uniek ten opzichte van [taken] door zo nodig `-2`, `-3`, … aan te
/// hangen. Zo blijven twee dia's met dezelfde kop toch los aanwijsbaar.
String uniqueAnchor(String seed, Set<String> taken) {
  if (!taken.contains(seed)) return seed;
  for (var n = 2; ; n++) {
    final candidate = '$seed-$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// De dia-lijst na het zetten of wissen van de sprong-uit van dia [index]
/// (#1162), of `null` als er niets verandert (ongeldige index, sprong naar
/// zichzelf, of al leeg).
///
/// [targetIndex] `null` wist de sprong. Anders krijgt de doeldia zo nodig een
/// uniek, bevroren anker — de gebruiker koos een dia, niet een anker — en wijst
/// [index] daarheen. Puur over de lijst zodat de notifier alleen nog hoeft te
/// muteren en dit los te toetsen valt.
List<Slide>? slidesWithJump(List<Slide> slides, int index, int? targetIndex) {
  if (index < 0 || index >= slides.length) return null;
  final out = List<Slide>.from(slides);
  if (targetIndex == null) {
    if (out[index].nextAnchor.isEmpty) return null;
    out[index] = out[index].copyWith(nextAnchor: '');
    return out;
  }
  if (targetIndex < 0 || targetIndex >= out.length || targetIndex == index) {
    return null;
  }
  var target = out[targetIndex];
  if (target.anchor.isEmpty) {
    final taken = {
      for (final s in out)
        if (s.anchor.isNotEmpty) s.anchor,
    };
    target = target.copyWith(
      anchor: uniqueAnchor(slugifyAnchor(target.title), taken),
    );
    out[targetIndex] = target;
  }
  out[index] = out[index].copyWith(nextAnchor: target.anchor);
  return out;
}
