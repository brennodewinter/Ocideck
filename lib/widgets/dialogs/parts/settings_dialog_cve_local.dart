// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De lokale CVE-database. Het punt ervan is niet snelheid maar zwijgen: zolang
// je online opzoekt, verraadt elke zoekopdracht wélk lek je onderzoekt. Ligt de
// lijst lokaal, dan gaat er niets naar buiten.
//
// Daar staat een prijs tegenover, en die verzwijgen we niet: een download van
// een paar honderd megabyte, ruim een gigabyte tijdelijk op schijf, en een
// kwartier wachten. Dat staat er vóórdat je op de knop drukt — niet in een
// voetnoot achteraf.
part of '../settings_dialog.dart';

extension _SettingsCveLocal on _SettingsDialogState {
  Widget _localCveSection(AppLocalizations l10n) {
    final local = ref.watch(localCveProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle(l10n.d('Lokale CVE-database')),
            const SizedBox(width: 8),
            PrivacyBadge(
              tooltip: l10n.d(
                'Met de CVE-lijst op je eigen apparaat blijft het opzoeken hier: er gaat geen zoekterm meer naar een server, en niemand kan zien welk lek je onderzoekt.',
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'Zet de volledige CVE-lijst op dit apparaat, zodat opzoeken offline gebeurt en je zoekterm nergens heen gaat. De database komt van CVE List V5 (het officiële CVE-programma, via GitHub).',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        // Bewust géén draaiend wieltje tijdens de eerste blik op schijf. Dat is
        // een stat-call van milliseconden — een spinner zou alleen even
        // opflikkeren. En een oneindige animatie die blijft draaien wanneer de
        // platformkanalen er niet zijn (widgettests, of een trage schijf) laat
        // elk scherm dat hem bevat nooit meer tot rust komen. De balk tijdens de
        // échte opbouw blijft wél: dáár wacht je minutenlang, en dan moet je
        // zien dat er iets gebeurt.
        if (local.loading)
          const SizedBox.shrink()
        else if (local.busy)
          _localCveProgress(l10n, local)
        else ...[
          if (local.stats != null) _localCveStats(l10n, local.stats!),
          if (local.failure != null) _localCveFailure(l10n, local.failure!),
          _localCveActions(l10n, local),
        ],
      ],
    );
  }

  /// De prijs, vóór de knop. Wie een half uur en een gigabyte kwijtraakt, hoort
  /// dat te weten voordat hij begint, niet erna.
  Widget _localCveCost(AppLocalizations l10n) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.amber500.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_outlined, size: 16, color: AppTheme.amber700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.d(
              'Dit is een grote download: ruim 500 MB binnenhalen, tijdelijk zo\'n 1,5 GB schijfruimte, en afhankelijk van je verbinding en apparaat al gauw tien tot dertig minuten werk. Daarna blijft er een index van enkele honderden megabytes staan. Op een verbinding die per megabyte betaalt, doe je dit liever niet.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ),
      ],
    ),
  );

  Widget _localCveProgress(AppLocalizations l10n, LocalCveState local) {
    final progress = local.progress!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localCvePhaseText(l10n, progress),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        // Een onbepaalde balk waar we de breuk niet kennen: een valse 0% die een
        // kwartier blijft staan, leest als "vastgelopen".
        LinearProgressIndicator(value: progress.fraction),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ref.read(localCveProvider.notifier).cancel(),
            icon: const Icon(Icons.close, size: 16),
            label: Text(l10n.d('Afbreken')),
          ),
        ),
      ],
    );
  }

  String _localCvePhaseText(AppLocalizations l10n, CveIngestProgress p) {
    switch (p.phase) {
      case CveIngestPhase.discovering:
        return l10n.d('De nieuwste uitgave opzoeken…');
      case CveIngestPhase.downloading:
        final total = p.total;
        if (total <= 0) return l10n.d('Binnenhalen…');
        return '${l10n.d('Binnenhalen…')} '
            '${_megabytes(p.received)} / ${_megabytes(total)} MB';
      case CveIngestPhase.extracting:
        return l10n.d('Uitpakken…');
      case CveIngestPhase.indexing:
        return '${l10n.d('Indexeren…')} ${p.records}';
    }
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(0);

  Widget _localCveStats(
    AppLocalizations l10n,
    LocalCveStats stats,
  ) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.iceBlue),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 15,
              color: AppTheme.accentFg,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.d(
                  'Lokaal beschikbaar — opzoeken gebeurt offline, er gaat geen zoekterm naar buiten.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${stats.records} ${l10n.d('CVE\'s')} · '
          '${_megabytes(stats.bytes)} MB · '
          '${stats.release} · ${stats.builtOn}',
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
      ],
    ),
  );

  Widget _localCveFailure(AppLocalizations l10n, CveIngestFailure failure) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 15, color: AppTheme.amber700),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                _localCveFailureText(l10n, failure),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
      );

  /// Elke reden zijn eigen zin: "mislukt" laat de gebruiker raden wat hij er nu
  /// aan kan doen.
  String _localCveFailureText(AppLocalizations l10n, CveIngestFailure failure) {
    switch (failure) {
      case CveIngestFailure.unsupportedPlatform:
        return l10n.d('Op het web nog niet beschikbaar');
      case CveIngestFailure.noConsent:
        return l10n.d(
          'Geef eerst toestemming voor uitgaand verkeer bij Privacy en classificatie.',
        );
      case CveIngestFailure.networkFailed:
        return l10n.d(
          'De CVE-lijst kon niet worden opgehaald. Controleer je verbinding en probeer het opnieuw; een half binnengehaalde lijst is weggegooid.',
        );
      case CveIngestFailure.invalidArchive:
        return l10n.d(
          'Het opgehaalde archief was niet wat we verwachtten en is geweigerd. Er is niets geïnstalleerd.',
        );
      case CveIngestFailure.cancelled:
        return l10n.d('Afgebroken. Er is niets half achtergebleven.');
      case CveIngestFailure.diskFull:
        return l10n.d(
          'Er was te weinig schijfruimte. De opbouw vraagt tijdelijk ruim 1,5 GB.',
        );
    }
  }

  Widget _localCveActions(AppLocalizations l10n, LocalCveState local) {
    final has = local.stats != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!has) _localCveCost(l10n),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () => _confirmLocalCveDownload(l10n, update: has),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(
                has ? l10n.d('Bijwerken') : l10n.d('Database ophalen'),
              ),
            ),
            if (has)
              TextButton.icon(
                onPressed: () => ref.read(localCveProvider.notifier).delete(),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: Text(l10n.d('Verwijderen')),
              ),
          ],
        ),
      ],
    );
  }

  /// Vraag het één keer, met het getal erbij. Een download van deze omvang
  /// hoort niet per ongeluk te beginnen.
  Future<void> _confirmLocalCveDownload(
    AppLocalizations l10n, {
    required bool update,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.d('Lokale CVE-database')),
        content: SizedBox(
          width: 420,
          child: Text(
            l10n.d(
              'Dit is een grote download: ruim 500 MB binnenhalen, tijdelijk zo\'n 1,5 GB schijfruimte, en afhankelijk van je verbinding en apparaat al gauw tien tot dertig minuten werk. Daarna blijft er een index van enkele honderden megabytes staan. Op een verbinding die per megabyte betaalt, doe je dit liever niet.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.d('Annuleren')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              update ? l10n.d('Bijwerken') : l10n.d('Database ophalen'),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(localCveProvider.notifier).download();
  }
}
