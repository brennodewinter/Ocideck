import '../../models/git_settings.dart';
import 'git_cli.dart';
import 'native_git_mirror_api.dart';

/// Op web bestaat er geen clone: het native plane is er niet (§8.3). De fabriek
/// wordt hier ook nooit aangeroepen — de probe geeft op web altijd `null` — maar
/// hij moet bestaan voor de conditionele export.
Future<NativeGitMirror?> createNativeGitMirror({
  required GitCli git,
  required GitRepoConfig config,
  required String token,
  String? baseDir,
}) async => null;
