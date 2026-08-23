import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/openkat/openkat_installation.dart';
import '../../platform/platform_features.dart';
import '../../services/openkat/openkat_error_messages.dart';
import '../../services/openkat/openkat_rocky_client.dart';
import '../../state/openkat_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../widgets/shell/openkat_import_action.dart';
import 'openkat_installation_wizard.dart';

/// Kiest installatie → organisatie → aggregaat-rapport, en begeleidt daarna
/// de JSON-export (pad B) of probeert REST-JSON (pad A, als beschikbaar).
class OpenKatServerReportDialog extends ConsumerStatefulWidget {
  const OpenKatServerReportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const OpenKatServerReportDialog(),
    );
  }

  @override
  ConsumerState<OpenKatServerReportDialog> createState() =>
      _OpenKatServerReportDialogState();
}

class _OpenKatServerReportDialogState
    extends ConsumerState<OpenKatServerReportDialog> {
  int _step = 0;
  OpenKatInstallation? _installation;
  OpenKatOrganization? _organization;
  OpenKatReportRef? _report;
  List<OpenKatOrganization> _orgs = const [];
  List<OpenKatReportRef> _reports = const [];
  bool _loading = false;
  OpenKatUserMessage? _error;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final list = ref.read(openKatInstallationsProvider);
      if (list.length == 1) {
        setState(() {
          _installation = list.first;
          _step = 1;
        });
        _loadOrgs();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final installations = ref.watch(openKatInstallationsProvider);
    return AlertDialog(
      title: Text(l10n.d('Rapportage van OpenKAT-server')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_installation != null) ...[
              Text(
                l10n
                    .d('Server: {name}')
                    .replaceAll('{name}', _installation!.name),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate700,
                ),
              ),
              Text(
                _installation!.host,
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
              const SizedBox(height: 12),
            ],
            _body(l10n, installations),
          ],
        ),
      ),
      actions: _actions(l10n, installations),
    );
  }

  Widget _body(AppLocalizations l10n, List<OpenKatInstallation> installations) {
    if (!supportsLocalProjectFolders) {
      return Text(
        l10n.d(
          'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.',
        ),
      );
    }
    if (_loading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.d(
                _step <= 1
                    ? 'Organisaties worden opgehaald…'
                    : 'Rapportages worden opgehaald…',
              ),
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      return Text(
        _error!.apply(l10n.d(_error!.source)),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return switch (_step) {
      0 => _pickServer(l10n, installations),
      1 => _pickOrg(l10n),
      2 => _pickReport(l10n),
      _ => _guidedExport(l10n),
    };
  }

  Widget _pickServer(
    AppLocalizations l10n,
    List<OpenKatInstallation> installations,
  ) {
    if (installations.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.d('Nog geen OpenKAT-server aangesloten.')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await OpenKatInstallationWizard.show(context);
              if (ok && mounted) setState(() {});
            },
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Server toevoegen…')),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup<String>(
          groupValue: _installation?.id,
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              _installation = installations.firstWhere((i) => i.id == id);
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in installations)
                RadioListTile<String>(
                  value: item.id,
                  title: Text(item.name),
                  subtitle: Text(item.host),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pickOrg(AppLocalizations l10n) {
    if (_orgs.isEmpty) {
      return Text(
        l10n.d(
          'Er zijn geen organisaties zichtbaar voor dit token. Vraag uw beheerder om toegang, of kies een andere server.',
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: RadioGroup<String>(
        groupValue: _organization?.code,
        onChanged: (code) {
          if (code == null) return;
          setState(() {
            _organization = _orgs.firstWhere((o) => o.code == code);
          });
        },
        child: ListView.builder(
          itemCount: _orgs.length,
          itemBuilder: (context, i) {
            final org = _orgs[i];
            return RadioListTile<String>(
              value: org.code,
              title: Text(org.name.isEmpty ? org.code : org.name),
              subtitle: Text(org.code),
            );
          },
        ),
      ),
    );
  }

  Widget _pickReport(AppLocalizations l10n) {
    if (_reports.isEmpty) {
      return Text(
        l10n.d(
          'Er staan geen organisatierapportages klaar op deze server. Maak in OpenKAT eerst een aggregaat-organisatierapport, of kies een andere organisatie.',
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: RadioGroup<String>(
        groupValue: _report?.id,
        onChanged: (id) {
          if (id == null) return;
          setState(() {
            _report = _reports.firstWhere((r) => r.id == id);
          });
        },
        child: ListView.builder(
          itemCount: _reports.length,
          itemBuilder: (context, i) {
            final report = _reports[i];
            final date = report.generatedAt;
            final dateLabel = date == null
                ? ''
                : '${date.toLocal().year}-'
                      '${date.toLocal().month.toString().padLeft(2, '0')}-'
                      '${date.toLocal().day.toString().padLeft(2, '0')}';
            return RadioListTile<String>(
              value: report.id,
              title: Text(report.name.isEmpty ? report.pk : report.name),
              subtitle: dateLabel.isEmpty ? null : Text(dateLabel),
            );
          },
        ),
      ),
    );
  }

  Widget _guidedExport(AppLocalizations l10n) {
    final chosen = l10n
        .d('Gekozen: {reportName} · {orgName} · {serverName}')
        .replaceAll('{reportName}', _report?.name ?? '')
        .replaceAll(
          '{orgName}',
          _organization?.name.isNotEmpty == true
              ? _organization!.name
              : (_organization?.code ?? ''),
        )
        .replaceAll('{serverName}', _installation?.name ?? '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('JSON-export uit OpenKAT'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.d(
            'OpenKAT levert de rapportage-inhoud als JSON-bestand. Exporteer in OpenKAT het gekozen rapport als JSON, en wijs dat bestand of de map hieraan.',
          ),
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.slate600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(chosen, style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
        const SizedBox(height: 14),
        if (_importing)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _pickJsonFile,
                icon: const Icon(Icons.description_outlined, size: 16),
                label: Text(l10n.d('JSON-bestand kiezen…')),
              ),
              OutlinedButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.d('Map met exports kiezen…')),
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _actions(
    AppLocalizations l10n,
    List<OpenKatInstallation> installations,
  ) {
    return [
      TextButton(
        onPressed: _importing
            ? null
            : () {
                if (_step == 0 || (_step == 1 && installations.length == 1)) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    _error = null;
                    if (_step == 3) {
                      _step = 2;
                    } else if (_step == 2) {
                      _step = 1;
                      _report = null;
                      _reports = const [];
                    } else if (_step == 1) {
                      _step = 0;
                      _organization = null;
                      _orgs = const [];
                    }
                  });
                }
              },
        child: Text(
          _step == 0 || (_step == 1 && installations.length == 1)
              ? l10n.d('Annuleren')
              : l10n.d('Terug'),
        ),
      ),
      if (_step < 3)
        FilledButton(
          onPressed: _importing ? null : _goNext,
          child: Text(_step == 2 ? l10n.d('Doorgaan') : l10n.d('Volgende')),
        ),
    ];
  }

  Future<void> _goNext() async {
    if (_step == 0) {
      if (_installation == null) return;
      setState(() => _step = 1);
      await _loadOrgs();
      return;
    }
    if (_step == 1) {
      if (_organization == null) return;
      setState(() => _step = 2);
      await _loadReports();
      return;
    }
    if (_step == 2) {
      if (_report == null) return;
      // Probeer pad A; bij ontbrekend endpoint → pad B (stap 3).
      final fetched = await _tryFetchJson();
      if (fetched) return;
      setState(() => _step = 3);
    }
  }

  Future<OpenKatRockyClient?> _client() async {
    final installation = _installation;
    if (installation == null) return null;
    final token = await ref
        .read(openKatProvider.notifier)
        .readToken(installation.id);
    if (token == null || token.trim().isEmpty) {
      setState(
        () => _error = const OpenKatUserMessage(
          'Er is geen toegangstoken. Plak het token van uw beheerder en probeer opnieuw.',
        ),
      );
      await ref
          .read(openKatProvider.notifier)
          .markInstallationChecked(
            id: installation.id,
            status: OpenKatInstallationStatus.tokenMissing,
          );
      return null;
    }
    return OpenKatRockyClient(installation: installation, token: token);
  }

  Future<void> _loadOrgs() async {
    setState(() {
      _loading = true;
      _error = null;
      _orgs = const [];
      _organization = null;
    });
    final client = await _client();
    if (client == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final orgs = await client.listOrganizations();
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _loading = false;
        if (orgs.length == 1) _organization = orgs.first;
      });
      await ref
          .read(openKatProvider.notifier)
          .markInstallationChecked(
            id: _installation!.id,
            status: OpenKatInstallationStatus.connected,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = openKatErrorMessage(e);
      });
      await ref
          .read(openKatProvider.notifier)
          .markInstallationChecked(
            id: _installation!.id,
            status: OpenKatInstallationStatus.failed,
          );
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
      _reports = const [];
      _report = null;
    });
    final client = await _client();
    final org = _organization;
    if (client == null || org == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final reports = await client.listAggregateReports(org.code);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        if (reports.length == 1) _report = reports.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = openKatErrorMessage(e);
      });
    }
  }

  /// Pad A: als Rocky `/json/` heeft, schrijf naar temp en start de wizard.
  Future<bool> _tryFetchJson() async {
    final client = await _client();
    final org = _organization;
    final report = _report;
    if (client == null || org == null || report == null) return false;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await client.fetchReportJson(
        reportPk: report.pk,
        organizationCode: org.code,
      );
      if (!mounted) return false;
      setState(() => _loading = false);
      if (body == null) return false;
      await _importJsonBody(body, preferredName: '${org.code}-report.json');
      return true;
    } catch (e) {
      // Auth/netwerkfout op pad A: toon fout, blijf op stap 2.
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = openKatErrorMessage(e);
      });
      return false;
    }
  }

  Future<void> _pickJsonFile() async {
    if (!supportsLocalProjectFolders) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: context.l10n.d('JSON-bestand kiezen…'),
    );
    final path = file?.path;
    if (path == null) return;
    final body = await File(path).readAsString();
    await _importJsonBody(body, preferredName: p.basename(path));
  }

  Future<void> _pickFolder() async {
    if (!supportsLocalProjectFolders) return;
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    );
    if (dir == null || !mounted) return;
    setState(() => _importing = true);
    Navigator.of(context).pop();
    await importOpenKatReports(context, ref, directoryOverride: dir);
  }

  Future<void> _importJsonBody(
    String body, {
    required String preferredName,
  }) async {
    setState(() => _importing = true);
    final temp = await Directory.systemTemp.createTemp('ocideck-openkat-');
    final file = File(p.join(temp.path, preferredName));
    await writeStringAtomic(file, body);
    if (!mounted) return;
    Navigator.of(context).pop();
    await importOpenKatReports(context, ref, directoryOverride: temp.path);
  }
}
