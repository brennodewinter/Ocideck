import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/log.dart';
import '../../services/ociserve/ociserve_gateway.dart';
import '../../state/ociserve_provider.dart';
import 'ociserve_file_browser.dart' show ociServeFileError;

class OciServeFileShares extends ConsumerStatefulWidget {
  const OciServeFileShares({
    super.key,
    required this.organizationId,
    this.target,
  });
  final String organizationId;
  final CatalogEntry? target;
  static Future<void> show(
    BuildContext context, {
    required String organizationId,
    CatalogEntry? target,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        OciServeFileShares(organizationId: organizationId, target: target),
  );
  @override
  ConsumerState<OciServeFileShares> createState() => _OciServeFileSharesState();
}

class _OciServeFileSharesState extends ConsumerState<OciServeFileShares> {
  List<ManagedFileShare> _shares = [];
  String? _cursor, _error, _link;
  bool _busy = false, _invalidated = false, _uncertainCreate = false;
  int _epoch = 0;
  // Retained across retries in this dialog. A lost response never creates a
  // second invisible link. Management recovers through list + rotation.
  final _createKey = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    ++_epoch;
    _link = null;
    super.dispose();
  }

  Future<T> _call<T>(Future<T> Function(OciServeApi, String) operation) => ref
      .read(ociServeProvider.notifier)
      .fileOperation(widget.organizationId, operation);

  Future<void> _run(Future<void> Function() action) async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = ociServeFileError(context, e));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool more = false}) => _run(() async {
    final page = await _call(
      (api, token) => api.fileShares(
        accessToken: token,
        organizationId: widget.organizationId,
        cursor: more ? _cursor : null,
      ),
    );
    if (!mounted || _invalidated) return;
    setState(() {
      _shares = more ? [..._shares, ...page.items] : page.items;
      _cursor = page.nextCursor;
    });
  });

  Future<void> _create() async {
    final options = await _ShareOptions.show(context, target: widget.target);
    if (options == null) return;
    if (!mounted || _invalidated) {
      options.clear();
      return;
    }
    await _run(() async {
      try {
        final result = await _call(
          (api, token) => api.createFileShare(
            accessToken: token,
            organizationId: widget.organizationId,
            fileId: widget.target!.id,
            requestKey: _createKey,
            expiresAt: options.expiry,
            password: options.password ?? '',
          ),
        );
        if (!mounted || _invalidated) return;
        setState(() {
          _link = result.link;
          _shares = [result, ..._shares.where((s) => s.id != result.id)];
          _uncertainCreate = true;
        });
      } catch (e) {
        if (mounted) setState(() => _uncertainCreate = true);
        rethrow;
      } finally {
        options.clear();
      }
    });
  }

  Future<void> _update(ManagedFileShare share, {bool rotate = false}) async {
    if (rotate &&
        !await _confirm(
          'Nieuwe link uitgeven?',
          'De oude link en bestaande ontgrendelingen werken daarna niet meer.',
        )) {
      return;
    }
    if (!mounted || _invalidated) return;
    final options = rotate
        ? null
        : await _ShareOptions.show(context, share: share);
    if (!rotate && options == null) return;
    if (!mounted || _invalidated) {
      options?.clear();
      return;
    }
    await _run(() async {
      try {
        final result = await _call(
          (api, token) => api.updateFileShare(
            accessToken: token,
            organizationId: widget.organizationId,
            share: share,
            rotate: rotate,
            expiresAt: options?.expiry,
            password: options?.password,
            clearPassword: options?.clearPassword ?? false,
          ),
        );
        if (!mounted || _invalidated) return;
        setState(() {
          _link = result.link;
          _shares = [for (final s in _shares) s.id == result.id ? result : s];
        });
      } finally {
        options?.clear();
      }
    });
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.d(title)),
          content: Text(context.l10n.d(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.d('Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.d('Bevestigen')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _revoke(ManagedFileShare share) async {
    if (!await _confirm(
      'Deellink intrekken?',
      'Ontvangers kunnen daarna geen bestanden meer ophalen. Reeds gedownloade kopieën blijven bestaan.',
    )) {
      return;
    }
    if (!mounted || _invalidated) return;
    await _run(() async {
      await _call(
        (api, token) => api.revokeFileShare(
          accessToken: token,
          organizationId: widget.organizationId,
          shareId: share.id,
        ),
      );
      if (!mounted || _invalidated) return;
      setState(() {
        _link = null;
        _shares = [
          for (final s in _shares)
            if (s.id != share.id) s,
        ];
      });
    });
  }

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Deellink gekopieerd.'))),
        );
      }
    } catch (error) {
      logWarning('OciServe: klembordactie mislukt (${error.runtimeType})');
      if (mounted) {
        setState(
          () => _error = context.l10n.d(
            'Kopiëren is mislukt. Selecteer en kopieer de link handmatig.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ociServeProvider, (old, next) {
      if (old != null &&
          (old.settings != next.settings ||
              old.account?.id != next.account?.id ||
              old.authenticated != next.authenticated ||
              old.status != next.status)) {
        ++_epoch;
        setState(() {
          _invalidated = true;
          _link = null;
          _shares = [];
          _busy = false;
          _error = context.l10n.d(
            'De sessie is gewijzigd. Open de bron opnieuw.',
          );
        });
      }
    });
    final l10n = context.l10n;
    final state = ref.watch(ociServeProvider);
    final org = state.memberships
        .where((m) => m.organizationId == widget.organizationId)
        .firstOrNull;
    return AlertDialog(
      title: Text(l10n.d('OciServe-deellinks beheren')),
      content: SizedBox(
        width: 650,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(org?.name ?? widget.organizationId),
            if (widget.target case final target?) ...[
              Text(target.name),
              Text(
                l10n.d(
                  target.directory
                      ? 'De server legt deze map en maximaal 2.000 items vast als alleen-lezen snapshot. Latere wijzigingen vallen buiten deze link.'
                      : 'De server deelt de gepubliceerde versie. Lokale wijzigingen worden niet geüpload.',
                ),
              ),
            ],
            Text(
              l10n.d(
                'Links zijn alleen bij aanmaak of rotatie zichtbaar. Aanpassen verbreekt bestaande ontgrendelingen.',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_uncertainCreate)
              Text(
                l10n.d(
                  'Vernieuw de lijst als het resultaat onzeker is. Geef vanuit de bestaande share een nieuwe link uit; maak geen tweede share.',
                ),
              ),
            if (_link case final link?) ...[
              SelectableText(link),
              TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: Text(l10n.d('Deellink kopiëren')),
              ),
            ],
            Expanded(
              child: ListView(
                children: [
                  for (final share in _shares)
                    ListTile(
                      title: Text(
                        share.targetName.isEmpty
                            ? '${l10n.d('Vastgelegde versie')} ${share.rootId}'
                            : share.targetName,
                      ),
                      subtitle: Text(
                        '${share.status} · ${share.expiresAt.toLocal()} (${share.expiresAt.toLocal().timeZoneName})\n${share.expiresAt.toIso8601String()} · ${l10n.d(share.passwordProtected ? 'Met wachtwoord' : 'Zonder wachtwoord')} · ${share.snapshotItems} / ${share.snapshotBytes} B',
                      ),
                      trailing: share.status == 'active'
                          ? PopupMenuButton<String>(
                              enabled: !_busy && !_invalidated,
                              tooltip: l10n.d('Deellink beheren'),
                              onSelected: (action) {
                                switch (action) {
                                  case 'edit':
                                    _update(share);
                                  case 'rotate':
                                    _update(share, rotate: true);
                                  case 'revoke':
                                    _revoke(share);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(l10n.d('Aanpassen')),
                                ),
                                PopupMenuItem(
                                  value: 'rotate',
                                  child: Text(l10n.d('Nieuwe link uitgeven')),
                                ),
                                PopupMenuItem(
                                  value: 'revoke',
                                  child: Text(l10n.d('Intrekken')),
                                ),
                              ],
                            )
                          : null,
                    ),
                  if (_cursor case final cursor?)
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
        if (widget.target != null)
          FilledButton(
            onPressed: _busy || _invalidated || _uncertainCreate
                ? null
                : _create,
            child: Text(l10n.d('Deellink maken')),
          ),
        TextButton(
          onPressed: _busy || _invalidated ? null : _load,
          child: Text(l10n.d('Vernieuwen')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }
}

class _ShareInput {
  _ShareInput(this.expiry, this.password, this.clearPassword);
  final DateTime? expiry;
  String? password;
  final bool clearPassword;
  void clear() => password = null;
}

class _ShareOptions extends StatefulWidget {
  const _ShareOptions({this.target, this.share});
  final CatalogEntry? target;
  final ManagedFileShare? share;
  static Future<_ShareInput?> show(
    BuildContext context, {
    CatalogEntry? target,
    ManagedFileShare? share,
  }) => showDialog<_ShareInput>(
    context: context,
    builder: (_) => _ShareOptions(target: target, share: share),
  );
  @override
  State<_ShareOptions> createState() => _ShareOptionsState();
}

class _ShareOptionsState extends State<_ShareOptions> {
  final _password = TextEditingController();
  late final _initialExpiry =
      widget.share?.expiresAt.toLocal().toIso8601String() ?? '';
  late final _expiry = TextEditingController(text: _initialExpiry);
  bool _clear = false;
  String? _error;
  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final value = _expiry.text.trim();
      final expiry = value.isEmpty
          ? null
          : widget.share != null && value == _initialExpiry
          ? widget.share!.expiresAt
          : parseShareExpiryInput(value);
      if (value.isNotEmpty && !value.contains('T')) {
        throw const FormatException();
      }
      validateShareExpiry(expiry, DateTime.now());
      validateSharePassword(_password.text);
      final result = _ShareInput(
        expiry?.toUtc(),
        _password.text.isEmpty ? null : _password.text,
        _clear,
      );
      _password.clear();
      Navigator.pop(context, result);
    } on FormatException {
      setState(
        () => _error = context.l10n.d(
          'Kies een tijdstip binnen 90 dagen en een wachtwoord van 8 tot 256 bytes, of laat het wachtwoord leeg.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        l10n.d(widget.share == null ? 'Deelopties' : 'Deellink aanpassen'),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Alleen lezen. Zonder eindtijd is een nieuwe link zeven dagen geldig; maximaal negentig dagen.',
              ),
            ),
            Text(
              '${l10n.d('Lokale tijdzone')}: ${DateTime.now().timeZoneName}',
            ),
            TextField(
              controller: _expiry,
              decoration: InputDecoration(
                labelText: l10n.d('Einddatum en tijd'),
                hintText: DateTime.now()
                    .add(const Duration(days: 7))
                    .toLocal()
                    .toIso8601String(),
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_clear,
              decoration: InputDecoration(
                labelText: l10n.d(
                  widget.share == null
                      ? 'Optioneel wachtwoord'
                      : 'Nieuw wachtwoord (leeg = ongewijzigd)',
                ),
              ),
            ),
            if (widget.share?.passwordProtected == true)
              CheckboxListTile(
                value: _clear,
                title: Text(l10n.d('Wachtwoord verwijderen')),
                onChanged: (v) => setState(() {
                  _clear = v ?? false;
                  if (_clear) _password.clear();
                }),
              ),
            Text(
              l10n.d(
                'Aanpassen maakt bestaande ontgrendelingen ongeldig. Ontvangers moeten de link opnieuw openen.',
              ),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.d('Bevestigen'))),
      ],
    );
  }
}
