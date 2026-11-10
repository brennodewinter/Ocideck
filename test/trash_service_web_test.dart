@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/trash_service.dart';

void main() {
  test(
    'browser refuses native trash without touching dart:io platform APIs',
    () async {
      final trash = TrashService();
      expect(trash.isSupported, isFalse);
      expect(await trash.moveToTrash('browser-copy.md'), isFalse);
    },
  );
}
