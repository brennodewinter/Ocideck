// Part of the settings_dialog library — see ../settings_dialog.dart.
// Zoeken door de instellingen. Er zijn er inmiddels te veel om te onthouden
// waar iets staat, dus je moet erop kunnen zoeken in plaats van te moeten weten
// onder welk tabblad de bouwers het hebben gehangen.
//
// De ankers komen gratis: élke sectiekop loopt door _sectionTitle, dus die
// registreert daar zijn eigen GlobalKey. Een treffer schakelt naar het tabblad,
// scrollt de sectie in beeld en laat hem oplichten — zonder dat er ergens in de
// tabbladen een regel voor hoefde te veranderen.
part of '../settings_dialog.dart';

/// Eén doorzoekbare instelling: waar hij staat, en waarop hij te vinden is.
///
/// [label] en [section] zijn de Nederlandse bronteksten — exact dezelfde
/// literals die de tabbladen aan `l10n.d(...)` geven. Ze worden hier opnieuw
/// door `d()` gehaald, zodat zoeken en ankeren in elke taal op dezelfde
/// vertaalde tekst uitkomen als wat er op het scherm staat.
///
/// Een handvol koppen en labels komt uit de oudere sleuteltabel (`l10n.t`) in
/// plaats van uit een Nederlandse bronstring. Daarvoor zijn [labelKey] en
/// [sectionKey]: staat er een sleutel, dan wint die. Zonder dat onderscheid
/// zou het anker in het Nederlands toevallig kloppen en in elke andere taal
/// stilletjes mis grijpen.
class SettingsSearchEntry {
  /// De titel van de instelling, zoals hij in het tabblad staat.
  final String? label;

  /// Idem, maar uit de sleuteltabel (`l10n.t`).
  final String? labelKey;

  /// De sectiekop erboven; tevens het anker om naartoe te scrollen. `null` voor
  /// de handvol instellingen die onder geen enkele kop hangen — die springen
  /// naar het tabblad zonder te scrollen.
  final String? section;

  /// Idem, maar uit de sleuteltabel (`l10n.t`).
  final String? sectionKey;

  /// Index van het tabblad in de zijbalk.
  final int tab;

  /// Extra zoektermen die níét op het scherm staan — synoniemen en de woorden
  /// die iemand intypt als hij de officiële term niet kent ("video", "youtube",
  /// "lettertype"). Nederlandstalig; ze staan naast de vertaalde tekst.
  final List<String> keywords;

  const SettingsSearchEntry({
    required this.tab,
    this.label,
    this.labelKey,
    this.section,
    this.sectionKey,
    this.keywords = const [],
  });

  String resolvedLabel(AppLocalizations l10n) =>
      labelKey != null ? l10n.t(labelKey!) : l10n.d(label ?? '');

  /// De sectietekst zoals `_sectionTitle` hem kreeg — en dus zoals het anker
  /// geregistreerd staat. Leeg wanneer de instelling onder geen kop hangt.
  String resolvedSection(AppLocalizations l10n) => sectionKey != null
      ? l10n.t(sectionKey!)
      : (section == null ? '' : l10n.d(section!));
}

extension _SettingsSearch on _SettingsDialogState {
  /// De namen van de tabbladen, in de volgorde van de zijbalk. Ook de index
  /// waar [SettingsSearchEntry.tab] naar wijst.
  List<String> _tabLabels(AppLocalizations l10n) => <String>[
    l10n.t('settingsGeneral'),
    l10n.d('App-thema'),
    l10n.d('Presentatiestijl'),
    l10n.d('Cockpit'),
    l10n.d('Licentie en Privacy'),
    l10n.d('Beveiliging'),
    l10n.d('AI-assistentie'),
    l10n.d('Nextcloud'),
    l10n.d('Checklists'),
    l10n.d('Uitbreidingen'),
    l10n.d('Documentatie'),
    l10n.d('Over OciDeck'),
  ];

  /// De sectiekop. Registreert zijn eigen anker en licht op wanneer een
  /// zoekresultaat hiernaartoe sprong.
  Widget _sectionTitle(String text) {
    final highlighted = _highlightedSection == text;
    return KeyedSubtree(
      key: _sectionKeys.putIfAbsent(text, GlobalKey.new),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: highlighted
            ? const EdgeInsets.fromLTRB(8, 6, 8, 8)
            : const EdgeInsets.only(bottom: 8),
        decoration: highlighted
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent, width: 2),
                color: AppTheme.accent.withValues(alpha: 0.06),
              )
            : null,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _settingsSearchField() {
    final l10n = context.l10n;
    return SizedBox(
      width: 260,
      height: 36,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => _rebuild(() => _searchQuery = v.trim()),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.d('Zoek een instelling'),
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.slate400),
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  splashRadius: 14,
                  tooltip: l10n.t('cancel'),
                  onPressed: _clearSettingsSearch,
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.iceBlue),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.iceBlue),
          ),
        ),
      ),
    );
  }

  void _clearSettingsSearch() {
    _searchController.clear();
    _rebuild(() => _searchQuery = '');
  }

  /// Treffers, gerangschikt op waar de zoekterm in de tekst begint — een
  /// instelling die ermee begint staat boven een die hem ergens middenin heeft.
  List<SettingsSearchEntry> _settingsSearchHits(AppLocalizations l10n) {
    final q = AppLocalizations.sortKey(_searchQuery);
    if (q.isEmpty) return const [];

    final scored = <({int score, SettingsSearchEntry entry})>[];
    for (final entry in kSettingsSearchIndex) {
      var best = -1;
      final haystack = [
        entry.resolvedLabel(l10n),
        entry.resolvedSection(l10n),
        ...entry.keywords,
      ];
      for (final hay in haystack) {
        if (hay.isEmpty) continue;
        final i = AppLocalizations.sortKey(hay).indexOf(q);
        if (i >= 0 && (best < 0 || i < best)) best = i;
      }
      if (best >= 0) scored.add((score: best, entry: entry));
    }
    scored.sort((a, b) => a.score.compareTo(b.score));
    return [for (final s in scored) s.entry];
  }

  Widget _settingsSearchResults(AppLocalizations l10n) {
    final hits = _settingsSearchHits(l10n);
    final labels = _tabLabels(l10n);

    return Material(
      color: AppTheme.slate50,
      child: hits.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  l10n.d('Geen instelling gevonden'),
                  style: TextStyle(fontSize: 13, color: AppTheme.slate500),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: hits.length,
              itemBuilder: (context, i) {
                final entry = hits[i];
                final tab = entry.tab >= 0 && entry.tab < labels.length
                    ? labels[entry.tab]
                    : '';
                final section = entry.resolvedSection(l10n);
                return ListTile(
                  dense: true,
                  title: Text(
                    entry.resolvedLabel(l10n),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    section.isEmpty ? tab : '$tab › $section',
                    style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                  ),
                  trailing: const Icon(Icons.arrow_forward, size: 16),
                  onTap: () => _jumpToSetting(entry, l10n),
                );
              },
            ),
    );
  }

  /// Spring naar de instelling: eerst het tabblad, dán pas scrollen — het anker
  /// van een niet-getoond tabblad heeft nog geen plek op het scherm.
  void _jumpToSetting(SettingsSearchEntry entry, AppLocalizations l10n) {
    final section = entry.resolvedSection(l10n);
    _clearSettingsSearch();
    _rebuild(() {
      _selectedTab = entry.tab;
      _highlightedSection = section.isEmpty ? null : section;
    });
    if (section.isEmpty) return; // hangt onder geen kop: tabblad is genoeg

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sectionKeys[section]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.15,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _highlightedSection == section) {
        _rebuild(() => _highlightedSection = null);
      }
    });
  }
}
