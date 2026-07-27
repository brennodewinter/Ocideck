import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/license_detect.dart';

/// Regression guard for the licence attribution of Flutter-SDK packages that
/// ship without their own LICENSE file.
///
/// Such a package is covered by the Flutter SDK's own BSD-3-Clause licence, but
/// [findLicenseFile] finds nothing in its directory, so [licenseForPackage]
/// leans on the [sdkNoLicense] allow-list to tell "SDK package, no own file"
/// apart from "genuinely unlicensed". When that list is incomplete the package
/// is reported as `NO LICENSE FILE`, which then leaks into the published CRA
/// SBOM as an apparently unlicensed component.
///
/// `fuchsia_remote_debug_protocol` (pulled transitively by `flutter_driver` /
/// `flutter_test`) was exactly that gap until it was added to the list.
void main() {
  group('licenseForPackage — Flutter-SDK packages without a LICENSE file', () {
    late Directory noLicenseDir;

    setUp(() {
      noLicenseDir = Directory.systemTemp.createTempSync('license_detect_test');
    });

    tearDown(() {
      noLicenseDir.deleteSync(recursive: true);
    });

    test('fuchsia_remote_debug_protocol is attributed to the Flutter SDK', () {
      // The concrete regression: this used to return `NO LICENSE FILE`.
      expect(
        licenseForPackage('fuchsia_remote_debug_protocol', noLicenseDir),
        'BSD-3-Clause (Flutter SDK)',
      );
    });

    test('every listed SDK package resolves to the SDK licence, not a gap', () {
      for (final name in sdkNoLicense) {
        expect(
          licenseForPackage(name, noLicenseDir),
          'BSD-3-Clause (Flutter SDK)',
          reason:
              '$name is in sdkNoLicense but did not resolve to the SDK '
              'licence — the allow-list and the branch have drifted apart',
        );
      }
    });

    test('a non-SDK package without a LICENSE file is still flagged', () {
      // The other branch must keep working: a real gap stays visible.
      expect(
        licenseForPackage('some_unlisted_package', noLicenseDir),
        'NO LICENSE FILE',
      );
    });
  });
}
