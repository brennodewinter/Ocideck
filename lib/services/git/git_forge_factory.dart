import '../../models/git_settings.dart';
import 'git_forge.dart';
import 'gitea_forge.dart';
import 'github_forge.dart';
import 'gitlab_forge.dart';

/// Bouw de adapter die bij [config] hoort.
///
/// Stond in `git_provider.dart`, maar is een pure constructor: de
/// settings-dialoog en de opslagprobe testen een verbinding die nog niet is
/// opgeslagen — er is dan geen connectionId om een provider op te draaien.
/// In de service-laag kan iedereen erbij zonder de state-laag binnen te
/// halen. De aanroeper sluit de forge zelf.
GitForge createGitForge({
  required GitRepoConfig config,
  required String token,
}) => switch (config.provider) {
  GitProvider.gitea => GiteaForge(config: config, token: token),
  GitProvider.github => GitHubForge(config: config, token: token),
  GitProvider.gitlab => GitLabForge(config: config, token: token),
};
