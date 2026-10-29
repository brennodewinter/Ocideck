/// Klein memo per object, zwak gekoppeld aan de levensduur van dat object.
///
/// Een globale LRU met een vast plafond valt om zodra een sequentiële
/// scan meer items leest dan het plafond: elk item verdringt het volgende
/// vlak voordat het weer nodig is, en elke toetsaanslag mist alles (#2622).
/// Een [Expando] leeft precies zo lang als het object dat de sleutel is —
/// een dia — en groeit dus niet los van het deck. [maxEntries] vangt de
/// paar geometrieën waarop dezelfde dia tegelijk getekend wordt (strook,
/// preview, raster, presentator, beamer); de oudste valt weg.
class IdentitySlotMemo<T extends Object, V> {
  IdentitySlotMemo(this.maxEntries, String debugName)
    : _slots = Expando<Map<Object, V>>(debugName);

  final int maxEntries;
  final Expando<Map<Object, V>> _slots;

  /// `null` wanneer er geen treffer is. Een treffer schuift naar het eind,
  /// zodat een volgende verdringing de langst onaangeroerde sleutel raakt.
  V? read(T host, Object key) {
    final map = _slots[host];
    if (map == null) return null;
    final value = map.remove(key);
    if (value == null) return null;
    map[key] = value;
    return value;
  }

  void write(T host, Object key, V value) {
    final map = _slots[host] ??= <Object, V>{};
    map.remove(key);
    map[key] = value;
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
  }
}
