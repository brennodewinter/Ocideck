/// Is [after] dezelfde verzameling rijen als [before] in een andere volgorde?
///
/// Alleen dán was de bewerking een sortering of rijverplaatsing — een discrete
/// handeling die een eigen undo-stap verdient, geen voortzetting van lopend
/// typewerk (#2486). Typen, plakken en rij-invoeging veranderen de
/// verzameling zelf en vallen hier buiten.
///
/// De vergelijking is inhoudelijk (rij per rij als string met een
/// stuurteken-scheiding, zoals de fingerprint in `TableEditController`), dus
/// duplicaten tellen correct mee en een netto-identieke tabel is géén
/// permutatie.
bool isTableRowPermutation(
  List<List<String>>? before,
  List<List<String>>? after,
) {
  if (before == null || after == null) return false;
  if (identical(before, after) || before.length != after.length) return false;
  // Minder dan twee rijen kan niet van volgorde wisselen.
  if (before.length < 2) return false;
  String keyOf(List<String> row) => row.join('\u0001');
  final remaining = <String, int>{};
  for (final row in before) {
    final key = keyOf(row);
    remaining[key] = (remaining[key] ?? 0) + 1;
  }
  var moved = false;
  for (var i = 0; i < after.length; i++) {
    final key = keyOf(after[i]);
    final left = (remaining[key] ?? 0) - 1;
    if (left < 0) return false;
    remaining[key] = left;
    if (keyOf(before[i]) != key) moved = true;
  }
  return moved;
}
