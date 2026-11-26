import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ociserve_file_origin.dart';
import '../../models/ociserve_models.dart';
import '../../services/ociserve/ociserve_gateway.dart';
import '../../services/ociserve/ociserve_auth.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import 'ociserve_file_shares.dart';
import 'ociserve_passkeys_button.dart';

class OciServeFileSelection {
  const OciServeFileSelection(this.bytes, this.entry, this.origin);
  final Uint8List bytes;
  final CatalogEntry entry;
  final OciServeFileOrigin origin;
}

String ociServeFileError(BuildContext context, Object error) {
  final code = error is OciServeException ? error.code : 'invalid_response';
  final status = error is OciServeException ? error.statusCode : null;
  return context.l10n.d(switch ((code, status)) {
    ('browser_refused', _) =>
      'Sta het aanmeldvenster toe en klik opnieuw op Inloggen.',
    ('cancelled', _) => 'De sessie is gewijzigd. Open de bron opnieuw.',
    ('share_password_required', _) =>
      'Voer het wachtwoord in of probeer opnieuw.',
    ('share_rate_limited', _) || (_, 429) =>
      'Te veel pogingen. Wacht minstens een minuut en probeer opnieuw.',
    ('share_unavailable', _) =>
      'Deze deellink is niet beschikbaar of is verlopen of ingetrokken.',
    ('response_too_large', _) =>
      'Dit bestand is te groot om te openen (maximaal 32 MB).',
    ('file_changed', _) || (_, 412) || (_, 409) =>
      'De versie is gewijzigd. Vernieuw het overzicht en probeer opnieuw.',
    ('unsupported_file', _) => 'Dit bestandstype wordt niet ondersteund.',
    (_, 403) => 'U hebt geen toegang tot deze bestanden of deze actie.',
    (_, 404) || (_, 501) =>
      'Deze server ondersteunt deze bron niet, of het doel bestaat niet meer.',
    ('not_authenticated', _) ||
    ('session_expired', _) ||
    (_, 401) => 'Meld u opnieuw aan bij OciServe.',
    ('desktop_only', _) =>
      'Deze installatie ondersteunt OciServe-aanmelding alleen in de desktopapp.',
    _ =>
      'OciServe kon het verzoek niet afronden. Controleer de verbinding en probeer opnieuw.',
  });
}

/// One browser shell for the tenant catalog and an isolated public snapshot.
class OciServeFileBrowser extends ConsumerStatefulWidget {
  const OciServeFileBrowser({super.key, this.publicFiles});
  final OciServePublicFiles? publicFiles;
  static Future<OciServeFileSelection?> show(
    BuildContext context, {
    OciServePublicFiles? publicFiles,
  }) => showDialog<OciServeFileSelection>(
    context: context,
    builder: (_) => OciServeFileBrowser(publicFiles: publicFiles),
  );
  @override
  ConsumerState<OciServeFileBrowser> createState() =>
      _OciServeFileBrowserState();
}

class _OciServeFileBrowserState extends ConsumerState<OciServeFileBrowser> {
  String? _org;
  CatalogPage? _page;
  List<CatalogEntry> _items = [];
  List<CatalogCrumb> _crumbs = [];
  String? _error;
  bool _busy = false, _unlocked = false;
  int _epoch = 0;
  OciServeRequestScope _scope = OciServeRequestScope();
  void _cancelWork() {
    _scope.cancel();
    _scope = OciServeRequestScope();
  }

  final _password = TextEditingController();
  OciServeState? _session;
  bool get _public => widget.publicFiles != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_public) {
        _unlock();
      } else {
        _syncSession(ref.read(ociServeProvider));
      }
    });
  }

  @override
  void dispose() {
    ++_epoch;
    _scope.cancel();
    _password.clear();
    _password.dispose();
    widget.publicFiles?.close();
    super.dispose();
  }

  void _syncSession(OciServeState state) {
    final old = _session;
    _session = state;
    if (old != null &&
        (old.settings != state.settings ||
            old.account?.id != state.account?.id ||
            old.authenticated != state.authenticated ||
            old.status != state.status)) {
      ++_epoch;
      _cancelWork();
      setState(() {
        _page = null;
        _items = [];
        _crumbs = [];
        _busy = false;
        _error = context.l10n.d(
          'De sessie is gewijzigd. Open de bron opnieuw.',
        );
        _org = null;
      });
      return;
    }
    if (_org == null && state.authenticated && state.memberships.isNotEmpty) {
      _org = state.memberships.first.organizationId;
      _load();
    }
  }

  Future<void> _unlock() async {
    _cancelWork();
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    final password = _password.text;
    _password.clear();
    try {
      await widget.publicFiles!.unlock(password: password);
      _password.clear();
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() {
        _unlocked = true;
        _busy = false;
      });
      await _load();
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = ociServeFileError(context, e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _load({
    String? folderId,
    bool more = false,
    List<CatalogCrumb>? crumbs,
  }) async {
    _cancelWork();
    final epoch = ++_epoch;
    final org = _org;
    final cursor = more ? _page?.nextCursor : null;
    final target = folderId ?? (more ? _page?.folder.id : null);
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _page = null;
        _items = [];
        if (crumbs != null) _crumbs = crumbs;
      }
    });
    try {
      final CatalogPage page;
      if (_public) {
        page = await widget.publicFiles!.browse(nodeId: target, cursor: cursor);
      } else {
        if (org == null) throw const OciServeException('not_authenticated');
        page = await ref
            .read(ociServeProvider.notifier)
            .fileOperation(
              org,
              (api, token) => api.files(
                accessToken: token,
                organizationId: org,
                folderId: target ?? 'root',
                cursor: cursor,
              ),
              scope: _scope,
            );
      }
      if (!mounted || epoch != _epoch || org != _org) return;
      setState(() {
        _page = page;
        _items = more ? [..._items, ...page.items] : page.items;
        if (!_public) {
          _crumbs = page.breadcrumbs;
        } else if (_crumbs.isEmpty) {
          _crumbs = [CatalogCrumb(page.folder.id, page.folder.name)];
        }
        _busy = false;
      });
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
          _error = ociServeFileError(context, e);
        });
      }
    }
  }

  Future<void> _open(CatalogEntry entry) async {
    if (entry.directory) {
      await _load(
        folderId: entry.id,
        crumbs: [..._crumbs, CatalogCrumb(entry.id, entry.name)],
      );
      return;
    }
    _cancelWork();
    final epoch = ++_epoch;
    final org = _org;
    final server = _public
        ? widget.publicFiles!.link.origin.toString()
        : ref.read(ociServeProvider).settings.normalizedBaseUrl;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = _public
          ? await widget.publicFiles!.download(entry)
          : await ref
                .read(ociServeProvider.notifier)
                .fileOperation(
                  org!,
                  (api, token) => api.fileContent(
                    accessToken: token,
                    organizationId: org,
                    entry: entry,
                  ),
                  scope: _scope,
                );
      if (!mounted || epoch != _epoch || org != _org) return;
      Navigator.pop(
        context,
        OciServeFileSelection(
          bytes,
          entry,
          OciServeFileOrigin(
            server: server,
            organizationId: org,
            fileId: entry.id,
            name: entry.name,
            etag: entry.etag,
            publicShare: _public,
          ),
        ),
      );
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
          _error = ociServeFileError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_public) ref.listen(ociServeProvider, (_, next) => _syncSession(next));
    final state = ref.watch(ociServeProvider);
    final l10n = context.l10n;
    final membership = state.memberships
        .where((m) => m.organizationId == _org)
        .firstOrNull;
    return AlertDialog(
      title: Text(
        l10n.d(_public ? 'OciServe-deellink openen' : 'OciServe-bestanden'),
      ),
      content: SizedBox(
        width: 680,
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_public) ...[
              if (!state.authenticated)
                Text(
                  l10n.d(
                    'Meld u eerst aan bij OciServe via Instellingen → eLearning.',
                  ),
                ),
              if (state.memberships.isNotEmpty)
                DropdownButton<String>(
                  value: _org,
                  isExpanded: true,
                  hint: Text(l10n.d('Organisatie')),
                  items: [
                    for (final m in state.memberships)
                      DropdownMenuItem(
                        value: m.organizationId,
                        child: Text(m.name.isEmpty ? m.organizationId : m.name),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    ++_epoch;
                    setState(() {
                      _org = id;
                      _page = null;
                      _items = [];
                      _crumbs = [];
                    });
                    _load();
                  },
                ),
              if (membership != null && !membership.canBrowseFiles)
                Text(
                  l10n.d(
                    'De server bepaalt of u bestanden mag lezen. Bij ontbrekende rechten verschijnt een melding.',
                  ),
                ),
            ],
            Text(
              l10n.d(
                _public
                    ? 'Alleen-lezen snapshot. Na sluiten of verlopen is opnieuw ontgrendelen nodig.'
                    : 'Openen maakt een lokale kopie. Opslaan wijzigt het serverbestand niet.',
              ),
            ),
            if (_public && !_unlocked) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.d('Wachtwoord (indien vereist)'),
                ),
                onSubmitted: (_) {
                  if (!_busy) _unlock();
                },
              ),
              TextButton(
                onPressed: _busy ? null : _unlock,
                child: Text(l10n.d('Ontgrendelen')),
              ),
            ],
            _breadcrumbs(),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_error != null && (!_public || _unlocked))
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _load(folderId: _crumbs.lastOrNull?.id),
                child: Text(l10n.d('Opnieuw proberen')),
              ),
            if (_page != null &&
                _items.isEmpty &&
                _page!.folder.directory &&
                !_busy)
              Text(l10n.d('Deze map is leeg.')),
            Expanded(
              child: ListView(
                children: [
                  if (_page != null && !_page!.folder.directory)
                    _row(_page!.folder, membership),
                  for (final entry in _items) _row(entry, membership),
                  if (_page?.nextCursor case final cursor?)
                    if (cursor.isNotEmpty)
                      TextButton(
                        onPressed: _busy ? null : () => _load(more: true),
                        child: Text(l10n.d('Volgende pagina')),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_public && state.errorCode == 'web_step_up_required')
          const OciServePasskeysButton(),
        if (_public && _error != null) _browserFallback(),
        if (!_public && _org != null && membership?.canShareFiles == true)
          TextButton(
            onPressed: _busy
                ? null
                : () => OciServeFileShares.show(context, organizationId: _org!),
            child: Text(l10n.d('Deellinks beheren')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d(_busy ? 'Annuleren' : 'Sluiten')),
        ),
      ],
    );
  }

  Widget _browserFallback() => TextButton.icon(
    icon: const Icon(Icons.open_in_browser),
    label: Text(context.l10n.d('Openen in browser')),
    onPressed: () async {
      try {
        if (!await const ExternalOciServeBrowserLauncher().open(
          widget.publicFiles!.link.browserUri,
        )) {
          throw const OciServeException('browser_refused');
        }
      } catch (error) {
        if (mounted) {
          setState(() => _error = ociServeFileError(context, error));
        }
      }
    },
  );

  Widget _breadcrumbs() => _crumbs.isEmpty
      ? const SizedBox.shrink()
      : Wrap(
          children: [
            for (var i = 0; i < _crumbs.length; i++)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _load(
                        folderId: _crumbs[i].id,
                        crumbs: _crumbs.take(i + 1).toList(),
                      ),
                child: Text(
                  _crumbs[i].name.isEmpty
                      ? context.l10n.d('Hoofdmap')
                      : _crumbs[i].name,
                ),
              ),
          ],
        );

  Widget _row(CatalogEntry entry, OciServeMembership? membership) => ListTile(
    leading: Icon(
      entry.directory ? Icons.folder_outlined : Icons.description_outlined,
    ),
    title: Text(entry.name),
    subtitle: Text(
      entry.directory
          ? context.l10n.d('Map')
          : '${entry.size} B${entry.supported ? '' : ' · ${context.l10n.d('Niet ondersteund')}'}',
    ),
    enabled: !_busy && (entry.directory || entry.supported),
    onTap: () => _open(entry),
    trailing:
        !_public && membership?.canShareFiles == true && entry.id != 'root'
        ? IconButton(
            tooltip: context.l10n.d('Delen'),
            icon: const Icon(Icons.share_outlined),
            onPressed: _busy
                ? null
                : () => OciServeFileShares.show(
                    context,
                    organizationId: _org!,
                    target: entry,
                  ),
          )
        : null,
  );
}
