import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_installation.dart';
import '../../../services/openkat/openkat_error_messages.dart';
import '../../../services/openkat/openkat_rocky_client.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';

/// Korte wizard (max. 3 stappen) om een OpenKAT-server toe te voegen of te
/// bewerken. Labels uit `docs/design/OPENKAT_LIVE_UX.md`.
class OpenKatInstallationWizard extends ConsumerStatefulWidget {
  const OpenKatInstallationWizard({super.key, this.existing});

  /// Null = toevoegen; gezet = bewerken (zelfde id, token optioneel leeg).
  final OpenKatInstallation? existing;

  static Future<bool> show(
    BuildContext context, {
    OpenKatInstallation? existing,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => OpenKatInstallationWizard(existing: existing),
    );
    return result ?? false;
  }

  @override
  ConsumerState<OpenKatInstallationWizard> createState() =>
      _OpenKatInstallationWizardState();
}

class _OpenKatInstallationWizardState
    extends ConsumerState<OpenKatInstallationWizard> {
  int _step = 0;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _trustedInternal = false;
  bool _testing = false;
  bool _testOk = false;
  String? _testMessage;
  Map<String, String> _testMessageArgs = const {};
  String? _fieldError;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _url = TextEditingController(text: existing?.baseUrl ?? '');
    _token = TextEditingController();
    _trustedInternal = existing?.trustedInternal ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        _editing
            ? l10n.d('OpenKAT-server bewerken')
            : l10n.d('OpenKAT-server toevoegen'),
      ),
      content: SizedBox(
        width: 440,
        child: switch (_step) {
          0 => _stepNameUrl(l10n),
          1 => _stepToken(l10n),
          _ => _stepTest(l10n),
        },
      ),
      actions: _actions(l10n),
    );
  }

  Widget _stepNameUrl(AppLocalizations l10n) {
    final host = Uri.tryParse(_url.text.trim())?.host;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: l10n.d('Weergavenaam'),
            hintText: l10n.d('Bijvoorbeeld Productie of Acceptatie'),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _fieldError = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          decoration: InputDecoration(
            labelText: l10n.d('Adres van OpenKAT'),
            hintText: l10n.d('https://openkat.voorbeeld.nl'),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() => _fieldError = null),
        ),
        if (host != null && host.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.d('Verbinding met: {host}').replaceAll('{host}', host),
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _trustedInternal,
          onChanged: (v) => setState(() {
            _trustedInternal = v;
            _fieldError = null;
          }),
          title: Text(
            l10n.d('Eigen netwerk (LAN)'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Alleen voor OpenKAT op het eigen netwerk. Staat HTTP toe en laat privé-adressen toe. Uitgeschakeld: alleen HTTPS.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ),
        if (_fieldError != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.d(_fieldError!),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepToken(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _token,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.d('Toegangstoken'),
            hintText: _editing
                ? l10n.d('Laat leeg om het opgeslagen token te behouden')
                : l10n.d('Plak het token hier'),
          ),
          onChanged: (_) => setState(() => _fieldError = null),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d(
            'Vraag uw OpenKAT-beheerder om een API-token in het beheerdersscherm. Het token blijft op dit apparaat, in de sleutelhanger van uw besturingssysteem — niet in het deck.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600, height: 1.4),
        ),
        if (_fieldError != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.d(_fieldError!),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepTest(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_testing)
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Verbinding wordt getest…'),
                  style: TextStyle(fontSize: 13, color: AppTheme.slate700),
                ),
              ),
            ],
          )
        else if (_testMessage != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _testOk ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: _testOk
                    ? AppTheme.accentFg
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _localize(_testMessage!, _testMessageArgs),
                  style: TextStyle(
                    fontSize: 13,
                    color: _testOk
                        ? AppTheme.accentFg
                        : Theme.of(context).colorScheme.error,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            l10n.d(
              'Test de verbinding voordat u opslaat, zodat u weet dat naam, adres en token kloppen.',
            ),
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.slate600,
              height: 1.4,
            ),
          ),
      ],
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    return [
      if (_step == 0)
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Annuleren')),
        )
      else
        TextButton(
          onPressed: _testing
              ? null
              : () => setState(() {
                  _step -= 1;
                  _testMessage = null;
                  _testOk = false;
                }),
          child: Text(l10n.d('Terug')),
        ),
      if (_step < 2)
        FilledButton(onPressed: _goNext, child: Text(l10n.d('Volgende')))
      else ...[
        if (!_testOk)
          FilledButton(
            onPressed: _testing ? null : _runTest,
            child: Text(l10n.d('Verbinding testen')),
          ),
        if (_testOk)
          FilledButton(
            onPressed: _testing ? null : _save,
            child: Text(l10n.d('Opslaan')),
          ),
      ],
    ];
  }

  Future<void> _goNext() async {
    if (_step == 0) {
      final name = _name.text.trim();
      if (name.isEmpty) {
        setState(
          () =>
              _fieldError = 'Vul een weergavenaam in, bijvoorbeeld Productie.',
        );
        return;
      }
      final urlError = validateOpenKatBaseUrl(
        _url.text,
        trustedInternal: _trustedInternal,
      );
      if (urlError != null) {
        setState(() => _fieldError = urlError);
        return;
      }
      setState(() {
        _fieldError = null;
        _step = 1;
      });
      return;
    }
    if (_step == 1) {
      if (!_editing && _token.text.trim().isEmpty) {
        setState(
          () => _fieldError = 'Plak een toegangstoken om verder te gaan.',
        );
        return;
      }
      if (_editing && _token.text.trim().isEmpty) {
        final has = await ref
            .read(openKatProvider.notifier)
            .hasToken(widget.existing!.id);
        if (!has) {
          setState(
            () => _fieldError = 'Plak een toegangstoken om verder te gaan.',
          );
          return;
        }
      }
      setState(() {
        _fieldError = null;
        _step = 2;
        _testMessage = null;
        _testOk = false;
      });
      // Nieuwe installatie: meteen testen zodat "Opslaan" de natuurlijke
      // volgende stap is na succes.
      if (!_editing) {
        await _runTest();
      }
    }
  }

  String _localize(String source, Map<String, String> args) {
    var text = context.l10n.d(source);
    for (final entry in args.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  Future<String?> _resolveToken() async {
    final typed = _token.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_editing) {
      return ref.read(openKatProvider.notifier).readToken(widget.existing!.id);
    }
    return null;
  }

  OpenKatInstallation _draft() {
    if (_editing) {
      return widget.existing!.copyWith(
        name: _name.text.trim(),
        baseUrl: _url.text.trim(),
        trustedInternal: _trustedInternal,
        lastStatus: OpenKatInstallationStatus.unchecked,
        clearLastCheckedAt: true,
      );
    }
    return OpenKatInstallation.create(
      name: _name.text.trim(),
      baseUrl: _url.text.trim(),
      trustedInternal: _trustedInternal,
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testMessage = null;
      _testOk = false;
    });
    final token = await _resolveToken();
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage =
            'Er is geen toegangstoken. Plak het token van uw beheerder en probeer opnieuw.';
        _testMessageArgs = const {};
      });
      return;
    }
    final draft = _draft();
    final client = OpenKatRockyClient(installation: draft, token: token);
    if (!client.canSend) {
      final denial = openKatDenialMessage(client.denialReason);
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = denial.source;
        _testMessageArgs = denial.args;
      });
      return;
    }
    try {
      final orgs = await client.testConnection();
      final host = draft.host;
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        if (orgs.isEmpty) {
          _testMessage =
              'Verbonden met {host}. Er zijn nog geen organisaties zichtbaar voor dit token.';
          _testMessageArgs = {'host': host};
        } else {
          _testMessage = 'Verbonden met {host}. {n} organisatie(s) bereikbaar.';
          _testMessageArgs = {'host': host, 'n': '${orgs.length}'};
        }
      });
    } catch (e) {
      if (!mounted) return;
      final msg = openKatErrorMessage(e);
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = msg.source;
        _testMessageArgs = msg.args;
      });
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    final token = _token.text.trim();
    final notifier = ref.read(openKatProvider.notifier);
    if (_editing) {
      await notifier.updateInstallation(
        draft.copyWith(
          lastStatus: OpenKatInstallationStatus.connected,
          lastCheckedAt: DateTime.now().toUtc(),
        ),
        token: token.isEmpty ? null : token,
      );
    } else {
      await notifier.addInstallation(
        draft.copyWith(
          lastStatus: OpenKatInstallationStatus.connected,
          lastCheckedAt: DateTime.now().toUtc(),
        ),
        token: token,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
