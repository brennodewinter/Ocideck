// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (git-tab); all imports live in the main library
// file. Mirrors settings_dialog_webdav.dart: the git source is the WebDAV
// source with versioning added, so it is configured the same way.
part of '../settings_dialog.dart';

extension _SettingsGit on _SettingsDialogState {
  Widget _gitPanel(GitForm form) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Git-repository')),
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
            initialValue: form.provider,
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
              const DropdownMenuItem(
                value: GitProvider.github,
                child: Text('GitHub'),
              ),
              const DropdownMenuItem(
                value: GitProvider.gitlab,
                child: Text('GitLab'),
              ),
            ],
            onChanged: (v) =>
                _rebuild(() => form.provider = v ?? GitProvider.gitea),
          ),
        ),
        _webdavField(
          form.url,
          l10n.d('Server-URL'),
          hint: 'https://git.example.org',
          icon: Icons.dns_outlined,
        ),
        _webdavField(
          form.owner,
          l10n.d('Eigenaar'),
          hint: 'librekat',
          icon: Icons.person_outline,
        ),
        _webdavField(
          form.repo,
          l10n.d('Repository'),
          hint: 'decks',
          icon: Icons.folder_outlined,
        ),
        _webdavField(
          form.branch,
          l10n.d('Branch (optioneel)'),
          hint: 'main',
          icon: Icons.account_tree_outlined,
        ),
        _webdavField(
          form.token.field,
          l10n.d('Personal access token'),
          obscure: true,
          icon: Icons.key_outlined,
        ),
        CheckboxListTile(
          value: form.trusted,
          onChanged: (v) => _rebuild(() {
            form.trusted = v ?? false;
            // De vlag bepaalt of de host überhaupt gebeld mag worden, dus een
            // eerdere uitslag zegt niets meer.
            form.clearTestResult();
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
        _gitTestRow(l10n, form),
        _nativeGitStatus(l10n),
      ],
    );
  }

  /// De verbindingstest: de knop, de uitslag en wat de forge onderweg vertelde.
  Widget _gitTestRow(AppLocalizations l10n, GitForm form) {
    final message = form.testMessage;
    final (Color color, IconData icon) = form.testWarning
        ? (AppTheme.amber700, Icons.warning_amber_outlined)
        : form.testOk == true
        ? (AppTheme.teal, Icons.check_circle)
        : (AppTheme.danger600, Icons.error_outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: form.testing ? null : () => _testGitConnection(form),
          icon: form.testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 16),
          label: Text(l10n.d('Verbinding testen')),
        ),
        if (form.testCertRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(
              onPressed: () => _trustGitCertificate(form),
              icon: const Icon(Icons.verified_user_outlined, size: 16),
              label: Text(l10n.d('Certificaat bekijken')),
            ),
          ),
        if (form.testOk != null && message != null)
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
  Future<void> _testGitConnection(GitForm form) async {
    final l10n = context.l10n;
    final config = form.config;
    if (!config.isConfigured) {
      _rebuild(() {
        form.testOk = false;
        form.testWarning = false;
        form.testMessage = l10n.d('Vul server-URL, eigenaar en repository in');
      });
      return;
    }
    _rebuild(() {
      form.testing = true;
      form.clearTestResult();
    });
    final forge = createGitForge(config: config, token: form.token.field.text);
    RepoProbe? probe;
    String? error;
    var certRejected = false;
    try {
      probe = await forge.probe();
    } on GitForgeException catch (e) {
      error = _gitErrorText(l10n, e);
      certRejected = e.kind == GitForgeError.tls;
    } catch (e, st) {
      logError('SettingsDialog: git-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    } finally {
      forge.close();
    }
    if (!mounted) return;
    _rebuild(() {
      form.testing = false;
      form.testOk = error == null;
      form.testWarning = probe?.canPush == false;
      form.testMessage = error ?? _gitProbeSummary(l10n, form, probe!);
      form.testCertRejected = certRejected;
    });
  }

  /// Laat het certificaat zien en pin het als de gebruiker het vertrouwt.
  Future<void> _trustGitCertificate(GitForm form) async {
    final config = form.config;
    final origin = config.origin;
    if (origin == null) return;
    final fingerprint = await _confirmCertificate(
      origin: origin,
      host: config.host,
      allowPrivate: config.trustedInternal,
    );
    if (fingerprint == null || !mounted) return;
    _rebuild(() {
      form.pinnedCertSha256 = fingerprint;
      form.clearTestResult();
    });
    await _testGitConnection(form);
  }

  /// Vat samen wat de test opleverde, en neem de standaardbranch over.
  String _gitProbeSummary(
    AppLocalizations l10n,
    GitForm form,
    RepoProbe probe,
  ) {
    final parts = <String>[l10n.d('Verbinding gelukt')];
    final chosen = form.branch.text.trim();
    if (chosen.isEmpty) {
      // Nog niets ingevuld: neem over wat de forge zegt. Dit is het gangbare
      // geval, en het is de enige manier waarop een repo op `master` werkt
      // zonder dat de gebruiker dat hoeft te weten.
      form.branch.text = probe.defaultBranch;
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

  String _gitErrorText(AppLocalizations l10n, GitForgeException e) {
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
              AppTheme.accent,
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
