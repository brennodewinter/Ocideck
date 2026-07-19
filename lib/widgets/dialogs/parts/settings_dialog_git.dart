// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (git-tab); all imports live in the main library
// file. Mirrors settings_dialog_webdav.dart: the git source is the WebDAV
// source with versioning added, so it is configured the same way.
part of '../settings_dialog.dart';

extension _SettingsGit on _SettingsDialogState {
  /// De repo zoals hij nu in de velden staat. Vult een ontbrekend schema aan:
  /// "git.example.org" zonder `https://` is de meest gemaakte invoerfout, en
  /// stranden op een onparseerbare URL is een slechter antwoord dan aanvullen.
  GitRepoConfig _gitRepoFromFields() {
    var url = _gitUrl.text.trim();
    if (url.isNotEmpty && !url.contains('://')) url = 'https://$url';
    return GitRepoConfig(
      baseUrl: url,
      owner: _gitOwner.text.trim(),
      repo: _gitRepo.text.trim(),
      trustedInternal: _gitTrusted,
      provider: _gitProvider,
    );
  }

  Widget _gitPanel() {
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
            initialValue: _gitProvider,
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
                _rebuild(() => _gitProvider = v ?? GitProvider.gitea),
          ),
        ),
        _webdavField(
          _gitUrl,
          l10n.d('Server-URL'),
          hint: 'https://git.example.org',
          icon: Icons.dns_outlined,
        ),
        _webdavField(
          _gitOwner,
          l10n.d('Eigenaar'),
          hint: 'librekat',
          icon: Icons.person_outline,
        ),
        _webdavField(
          _gitRepo,
          l10n.d('Repository'),
          hint: 'decks',
          icon: Icons.folder_outlined,
        ),
        _webdavField(
          _gitToken,
          l10n.d('Personal access token'),
          obscure: true,
          icon: Icons.key_outlined,
        ),
        CheckboxListTile(
          value: _gitTrusted,
          onChanged: (v) => _rebuild(() => _gitTrusted = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            l10n.d('Vertrouwde interne server'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _nativeGitStatus(l10n),
      ],
    );
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
