import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_image_service.dart';

import 'support/form_photo_fixtures.dart';

void main() {
  test(
    'session photos are cleaned, bounded and isolated from other invites',
    () async {
      final photos = FormSessionImages();
      final image = jpegPhoto(gps: true);
      final batch = await photos.add('gerecht', {}, [() async => image]);
      expect(batch.refused, isEmpty);
      final path = batch.stored.single.path;
      expect(path, 'images/gerecht-1.jpg');
      expect(batch.scrubbedPaths, {path});
      expect(photos.read(path), isNot(equals(image)));
      expect((await photos.probe([path]))[path]?.exists, isTrue);
      expect(FormSessionImages().read(path), isNull);
    },
  );
}
