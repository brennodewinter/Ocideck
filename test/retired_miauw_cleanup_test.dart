import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/retired_miauw_cleanup_io.dart';

void main() {
  test(
    'removes downloaded data and preserves user documents, idempotently',
    () async {
      final support = await Directory.systemTemp.createTemp('retired_miauw_');
      addTearDown(() => support.delete(recursive: true));
      final cache = await Directory(
        '${support.path}/cve/work',
      ).create(recursive: true);
      await File('${cache.path}/bulk.zip').writeAsString('download');
      final document = File('${support.path}/report.miauw.json');
      await document.writeAsString('{"user":"content"}');
      await removeRetiredMiauwData(supportDirectory: support);
      await removeRetiredMiauwData(supportDirectory: support);
      expect(await Directory('${support.path}/cve').exists(), isFalse);
      expect(await document.readAsString(), '{"user":"content"}');
    },
  );

  test('does not follow a symlink to user data', () async {
    final support = await Directory.systemTemp.createTemp('retired_miauw_');
    final external = await Directory.systemTemp.createTemp('user_documents_');
    addTearDown(() async {
      await support.delete(recursive: true);
      await external.delete(recursive: true);
    });
    final document = File('${external.path}/report.md');
    await document.writeAsString('user content');
    await Link('${support.path}/cve').create(external.path);
    await removeRetiredMiauwData(supportDirectory: support);
    expect(await document.readAsString(), 'user content');
  });
}
