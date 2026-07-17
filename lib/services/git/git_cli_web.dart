import 'git_cli.dart';

GitCli createGitCli() => const UnavailableGitCli();

/// Op web is er geen subproces: het native plane bestaat niet (§8.3, §11). De
/// stub meldt dat eerlijk in plaats van te doen alsof.
class UnavailableGitCli implements GitCli {
  const UnavailableGitCli();

  @override
  bool get isSupported => false;

  @override
  Future<GitVersion?> probe() async => null;

  @override
  Future<GitResult> run(
    List<String> args, {
    List<String> operands = const [],
    required String workingDirectory,
    List<GitConfigOverride> config = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async => throw const GitCliException('Native git bestaat niet op web');
}
