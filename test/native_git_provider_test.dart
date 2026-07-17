@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/git_cli.dart';
import 'package:ocideck/state/git_provider.dart';

// nativeGitVersionProvider draait de probe één keer en geeft de versie door.
// De echte probe start een proces; hier vervangen we de GitCli door een fake,
// zodat het gedrag van de provider los van de machine te bewaken is.

class _FakeGitCli implements GitCli {
  _FakeGitCli(this._version);
  final GitVersion? _version;
  int probes = 0;

  @override
  bool get isSupported => true;

  @override
  Future<GitVersion?> probe() async {
    probes++;
    return _version;
  }

  @override
  Future<GitResult> run(
    List<String> args, {
    List<String> operands = const [],
    required String workingDirectory,
    List<GitConfigOverride> config = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async => throw UnimplementedError();
}

void main() {
  test('geeft de gevonden versie door', () async {
    final container = ProviderContainer(
      overrides: [
        gitCliProvider.overrideWithValue(_FakeGitCli(GitVersion(2, 54, 0))),
      ],
    );
    addTearDown(container.dispose);

    final version = await container.read(nativeGitVersionProvider.future);
    expect(version?.display, '2.54.0');
  });

  test('null wanneer git niet bruikbaar is', () async {
    final container = ProviderContainer(
      overrides: [gitCliProvider.overrideWithValue(_FakeGitCli(null))],
    );
    addTearDown(container.dispose);

    expect(await container.read(nativeGitVersionProvider.future), isNull);
  });

  test('probet maar één keer en onthoudt het', () async {
    final fake = _FakeGitCli(GitVersion(2, 40, 0));
    final container = ProviderContainer(
      overrides: [gitCliProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(nativeGitVersionProvider.future);
    await container.read(nativeGitVersionProvider.future);
    expect(fake.probes, 1);
  });
}
