// Het git-paneel van het instellingenvenster.
//
// Stond tot #631 als `extension _SettingsGit on _SettingsDialogState` in de
// gedeelde `part`-scope. Nu een gewone widget met dezelfde expliciete API als
// [S3Panel] en [WebdavPanel]; het is een ConsumerStatefulWidget omdat het de
// detectie van native git leest.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/git_settings.dart';
import '../../../services/git/git_forge.dart';
import '../../../state/git_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
import 'confirm_certificate.dart';
import 'git_form.dart';
import 'settings_section_title.dart';
import 'settings_text_field.dart';

class GitPanel extends ConsumerStatefulWidget {
  /// Wat het paneel bewerkt. Eigendom van het venster, zodat een half ingevulde
  /// repo het dichtklappen van dit paneel overleeft.
  final GitForm form;

  final ConfirmCertificate confirmCertificate;

  /// Meldt dat er aan [form] iets veranderde: de regel achter de
  /// verbindingsnaam toont de uitslag van de verbindingstest en staat buiten
  /// dit paneel.
  final VoidCallback onChanged;

  const GitPanel({
    super.key,
    required this.form,
    required this.confirmCertificate,
    required this.onChanged,
  });

  @override
  ConsumerState<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends ConsumerState<GitPanel> {
  GitForm get _form => widget.form;

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('Git-repository')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open presentaties uit een git-repository. Elke opgeslagen versie blijft bewaard. Het token wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        // De soort forge bepaalt welke adapter erachter komt: de REST-API's
        // verschillen te veel om te raden aan de URL.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<GitProvider>(
            initialValue: _form.provider,
            decoration: InputDecoration(
              labelText: l10n.d('Soort forge'),
              prefixIcon: const Icon(Icons.hub_outlined, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: GitProvider.gitea,
                child: Text(l10n.d('Forgejo of Gitea')),
              ),
              DropdownMenuItem(
                value: GitProvider.github,
                child: Text(l10n.d('GitHub')),
              ),
              DropdownMenuItem(
                value: GitProvider.gitlab,
                child: Text(l10n.d('GitLab')),
              ),
            ],
            onChanged: (v) =>
                _update(() => _form.provider = v ?? GitProvider.gitea),
          ),
        ),
        SettingsTextField(
          _form.url,
          l10n.d('Server-URL'),
          hint: l10n.d('https://git.librekat.nl'),
          icon: Icons.dns_outlined,
        ),
        SettingsTextField(
          _form.owner,
          l10n.d('Eigenaar'),
          hint: l10n.d('librekat'),
          icon: Icons.person_outline,
        ),
        SettingsTextField(
          _form.repo,
          l10n.d('Repository'),
          hint: l10n.d('decks'),
          icon: Icons.folder_outlined,
        ),
        SettingsTextField(
          _form.branch,
          l10n.d('Branch (optioneel)'),
          hint: l10n.d('main'),
          icon: Icons.account_tree_outlined,
        ),
        SettingsSecretField(_form.token.field, l10n.d('Personal access token')),
        _tokenScopeHelp(l10n, _form.provider),
        CheckboxListTile(
          value: _form.trusted,
          onChanged: (v) => _update(() {
            _form.trusted = v ?? false;
            // De vlag bepaalt of de host überhaupt gebeld mag worden, dus een
            // eerdere uitslag zegt niets meer.
            _form.clearTestResult();
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            l10n.d('Vertrouwde interne server'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Nodig wanneer de forge op een privé- of thuisnetwerk draait. Zonder deze vlag weigert de beveiliging een privé-adres.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        const SizedBox(height: 12),
        _testRow(l10n),
        _nativeGitStatus(l10n),
      ],
    );
  }

  /// Welke rechten het token nodig heeft — per forge anders, en de naam van de
  /// scope verschilt per forge. Proactief onder het tokenveld, niet pas nadat een
  /// verbindingstest faalt: je hoeft het niet eerst mis te hebben om te weten wat
  /// je moet aanvinken. Wijzigt mee met de gekozen soort forge.
  Widget _tokenScopeHelp(AppLocalizations l10n, GitProvider provider) {
    final text = switch (provider) {
      GitProvider.gitea => l10n.d(
        'Het token heeft lees- en schrijfrechten op de repository nodig. Gitea en Forgejo kennen geen server-side zoeken; OciDeck zoekt lokaal.',
      ),
      GitProvider.github => l10n.d(
        'Het token heeft de repo-scope nodig (of fijnmazig: Contents lezen en schrijven).',
      ),
      GitProvider.gitlab => l10n.d(
        'Het token heeft read_repository, write_repository en read_api nodig. Server-side zoeken vereist Advanced- of Exact Search.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: AppTheme.slate400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ),
        ],
      ),
    );
  }

  /// De verbindingstest: de knop, de uitslag en wat de forge onderweg vertelde.
  Widget _testRow(AppLocalizations l10n) {
    final message = _form.testMessage;
    final (Color color, IconData icon) = _form.testWarning
        ? (AppTheme.amber700, Icons.warning_amber_outlined)
        : _form.testOk == true
        ? (AppTheme.tealFg, Icons.check_circle)
        : (AppTheme.danger600, Icons.error_outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: _form.testing ? null : _testConnection,
          icon: _form.testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 16),
          label: Text(l10n.d('Verbinding testen')),
        ),
        if (_form.testCertRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(
              onPressed: _trustCertificate,
              icon: const Icon(Icons.verified_user_outlined, size: 16),
              label: Text(l10n.d('Certificaat bekijken')),
            ),
          ),
        if (_form.testOk != null && message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Test de repo achter de ingevulde velden.
  ///
  /// Anders dan bij WebDAV en S3 is "het werkte" hier niet het hele antwoord.
  /// Alles kan kloppen en de eerste opslag alsnog stranden omdat de branch
  /// anders heet of het token alleen mag lezen — dus melden we wat de forge
  /// onderweg zei, en nemen we de standaardbranch meteen over.
  Future<void> _testConnection() async {
    final l10n = context.l10n;
    final config = _form.config;
    if (!config.isConfigured) {
      _update(() {
        _form.testOk = false;
        _form.testWarning = false;
        _form.testMessage = l10n.d('Vul server-URL, eigenaar en repository in');
      });
      return;
    }
    _update(() {
      _form.testing = true;
      _form.clearTestResult();
    });
    final forge = createGitForge(config: config, token: _form.token.field.text);
    RepoProbe? probe;
    String? error;
    var certRejected = false;
    try {
      probe = await forge.probe();
    } on GitForgeException catch (e) {
      error = _errorText(l10n, e);
      certRejected = e.kind == GitForgeError.tls;
    } catch (e, st) {
      logError('SettingsDialog: git-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    } finally {
      forge.close();
    }
    if (!mounted) return;
    _update(() {
      _form.testing = false;
      _form.testOk = error == null;
      _form.testWarning = probe?.canPush == false;
      _form.testMessage = error ?? _probeSummary(l10n, probe!);
      _form.testCertRejected = certRejected;
    });
  }

  /// Laat het certificaat zien en pin het als de gebruiker het vertrouwt.
  Future<void> _trustCertificate() async {
    final config = _form.config;
    final origin = config.origin;
    if (origin == null) return;
    final fingerprint = await widget.confirmCertificate(
      origin: origin,
      host: config.host,
      allowPrivate: config.trustedInternal,
    );
    if (fingerprint == null || !mounted) return;
    _update(() {
      _form.pinnedCertSha256 = fingerprint;
      _form.clearTestResult();
    });
    await _testConnection();
  }

  /// Vat samen wat de test opleverde, en neem de standaardbranch over.
  String _probeSummary(AppLocalizations l10n, RepoProbe probe) {
    final parts = <String>[l10n.d('Verbinding gelukt')];
    final chosen = _form.branch.text.trim();
    if (chosen.isEmpty) {
      // Nog niets ingevuld: neem over wat de forge zegt. Dit is het gangbare
      // geval, en het is de enige manier waarop een repo op `master` werkt
      // zonder dat de gebruiker dat hoeft te weten.
      _form.branch.text = probe.defaultBranch;
      parts.add(
        '${l10n.d('de standaardbranch heet')} "${probe.defaultBranch}" — '
        '${l10n.d('die wordt voortaan gebruikt')}',
      );
    } else if (chosen != probe.defaultBranch) {
      // Wél iets ingevuld en het wijkt af: melden, niet overschrijven. Wie een
      // andere branch intypt, bedoelt dat — dat is het hele punt van het veld.
      parts.add(
        '${l10n.d('let op: de standaardbranch is')} "${probe.defaultBranch}", '
        '${l10n.d('jij werkt op')} "$chosen"',
      );
    }
    if (probe.isEmpty) {
      parts.add(l10n.d('de repository is nog leeg; de eerste opslag vult hem'));
    }
    if (probe.canPush == false) {
      parts.add(
        l10n.d('let op: dit token mag alleen lezen, dus opslaan zal mislukken'),
      );
    }
    return '${parts.join(' — ')}.';
  }

  String _errorText(AppLocalizations l10n, GitForgeException e) {
    return switch (e.kind) {
      GitForgeError.auth => l10n.d(
        'Aanmelden mislukt — controleer het token. Het heeft leesrechten op de repository nodig, en schrijfrechten om te kunnen opslaan.',
      ),
      GitForgeError.forbidden => l10n.d(
        'Het token is geldig, maar mag dit niet — geef het meer rechten op de repository.',
      ),
      GitForgeError.notFound => l10n.d(
        'Repository niet gevonden — of je token mag hem niet zien. Controleer eigenaar en repositorynaam.',
      ),
      GitForgeError.unknownHost => l10n.d(
        'De servernaam bestaat niet. Controleer de server-URL op een typefout.',
      ),
      GitForgeError.blockedHost => l10n.d(
        'De server staat op een privé-adres. Vink "Vertrouwde interne server" aan om verbinding toe te staan.',
      ),
      GitForgeError.config => l10n.d('Ongeldige server-URL'),
      GitForgeError.tooLarge => l10n.d(
        'Het antwoord van de server was te groot',
      ),
      GitForgeError.malformed => l10n.d(
        'Dit adres antwoordt niet als een forge. Klopt de soort forge die je hebt gekozen?',
      ),
      // Bereikbaar, maar de forge zelf gaf een fout — iets anders dan
      // "verbinding mislukt", en het vraagt om iets anders van de gebruiker.
      GitForgeError.tls => l10n.d(
        'Het certificaat van de forge wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.',
      ),
      GitForgeError.server => l10n.d(
        'De forge gaf een fout. Probeer het later opnieuw.',
      ),
      GitForgeError.network => l10n.d('Verbinding mislukt'),
    };
  }

  /// Meldt of er bruikbaar native `git` op deze machine staat. Het lezen van de
  /// provider is meteen de aanleiding om te detecteren (§8.4: nooit bij het
  /// opstarten, wél zodra de gebruiker de git-instellingen opent). Met native
  /// git wordt opslaan een echte lokale commit met historie; zonder valt alles
  /// terug op het REST-pad, dat op elk platform werkt.
  Widget _nativeGitStatus(AppLocalizations l10n) {
    final probe = ref.watch(nativeGitVersionProvider);
    final (IconData icon, Color color, String text) = probe.when(
      loading: () => (
        Icons.hourglass_empty,
        AppTheme.slate400,
        l10n.d('Native git: bezig met detecteren…'),
      ),
      error: (_, _) => (
        Icons.info_outline,
        AppTheme.slate400,
        l10n.d('Native git: niet gevonden — het REST-pad wordt gebruikt'),
      ),
      data: (version) => version == null
          ? (
              Icons.info_outline,
              AppTheme.slate400,
              l10n.d('Native git: niet gevonden — het REST-pad wordt gebruikt'),
            )
          : (
              Icons.check_circle_outline,
              AppTheme.accentFg,
              '${l10n.d('Native git gevonden:')} ${version.display} — '
                  '${l10n.d('echte offline-historie mogelijk')}',
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: color)),
          ),
        ],
      ),
    );
  }
}
