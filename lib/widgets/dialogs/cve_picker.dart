import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cve_hit.dart';
import '../../models/settings.dart';
import '../../services/cve_search_service.dart';
import '../../state/consent_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';

/// Look up a CVE by its id pattern via an online NVD mirror (see
/// [CveSearchService]). Gated on the **CVE opzoeken** setting **and** outbound
/// consent, and desktop-only (no web) — fail-closed, offline-first. Returns the
/// chosen CVE id (or null on cancel); the finding editor appends it to the CVE
/// field. The CVSS 4.0 vector of the finding is never overwritten.
class CvePicker extends ConsumerStatefulWidget {
  const CvePicker({super.key, this.service});

  /// Injected in tests so the picker never touches the network; null uses the
  /// default service against the configured mirror.
  final CveSearchService? service;

  static Future<String?> show(
    BuildContext context, {
    CveSearchService? service,
  }) => showDialog<String>(
    context: context,
    builder: (_) => CvePicker(service: service),
  );

  @override
  ConsumerState<CvePicker> createState() => _CvePickerState();
}

class _CvePickerState extends ConsumerState<CvePicker> {
  final _query = TextEditingController();
  bool _loading = false;
  CveSearchResult? _result;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final settings = ref.read(settingsProvider);
    final base = settings.cveApiBaseUrl.trim().isEmpty
        ? AppSettings.defaultCveApiBaseUrl
        : settings.cveApiBaseUrl.trim();
    final service = widget.service ?? defaultCveSearchService(base);
    setState(() {
      _loading = true;
      _result = null;
    });
    final res = await service.search(_query.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled =
        !kIsWeb &&
        ref.watch(settingsProvider).allowCveLookup &&
        ref.watch(consentProvider).hasAccepted;
    return AlertDialog(
      title: Text(l10n.d('CVE opzoeken')),
      content: SizedBox(
        width: 480,
        height: 440,
        child: enabled ? _body(context) : _disabled(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
      ],
    );
  }

  Widget _disabled(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          kIsWeb
              ? l10n.d('CVE opzoeken is niet beschikbaar in de webversie.')
              : l10n.d(
                  'Zet CVE opzoeken (online) aan in Instellingen → Beveiliging om online in CVE\'s te zoeken.',
                ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppTheme.slate500),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: l10n.d('Zoek op CVE-id, bijv. 2021-44228'),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward, size: 18),
              tooltip: l10n.d('Zoeken'),
              onPressed: _loading ? null : _run,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _results(context)),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final result = _result;
    if (result == null) {
      return Center(
        child: Text(
          l10n.d('Typ een (deel van een) CVE-id en zoek.'),
          style: TextStyle(fontSize: 13, color: AppTheme.slate500),
        ),
      );
    }
    if (result.failure == CveSearchFailure.tooShort) {
      return Center(child: Text(l10n.d('Typ minstens 3 tekens.')));
    }
    if (result.failure == CveSearchFailure.network) {
      return Center(child: Text(l10n.d('Kon de CVE-bron niet bereiken.')));
    }
    if (result.hits.isEmpty) {
      return Center(child: Text(l10n.d('Geen CVE gevonden.')));
    }
    return ListView.separated(
      itemCount: result.hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _tile(context, result.hits[i]),
    );
  }

  Widget _tile(BuildContext context, CveHit hit) {
    final score = hit.cvssScore == null
        ? ''
        : ' · ${hit.cvssScore!.toStringAsFixed(1)}';
    final sev = hit.cvssSeverity.isEmpty ? '' : ' · ${hit.cvssSeverity}';
    return ListTile(
      title: Text('${hit.id}$sev$score'),
      subtitle: hit.description.isEmpty
          ? null
          : Text(hit.description, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right, color: AppTheme.slate400),
      onTap: () => Navigator.of(context).pop(hit.id),
    );
  }
}
