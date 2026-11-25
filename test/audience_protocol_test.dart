import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/presentation/audience_protocol.dart';

void main() {
  test('rejects unknown methods in both directions', () {
    const renamed = MethodCall('renamedMethod');
    expect(() => AudienceMethod.decode(renamed), throwsFormatException);
    expect(() => PresenterMethod.decode(renamed), throwsFormatException);
    expect(
      () => PresenterMethod.decode(const MethodCall('update')),
      throwsFormatException,
    );
  });

  test('rejects missing or malformed required fields before dispatch', () {
    const invalidSnapshots = [
      MethodCall('update', {'seq': 3}),
      MethodCall('replaceDeck', {'index': 0}),
      MethodCall('laser', {
        'index': 0,
        'point': [0.4],
      }),
      MethodCall('tableUpdate', {
        'slideIndex': 0,
        'tableRows': ['row'],
      }),
      MethodCall('chartHover', {'index': 0, 'seq': '4', 'hover': null}),
    ];
    for (final call in invalidSnapshots) {
      expect(() => AudienceMethod.decode(call), throwsFormatException);
    }
    expect(
      () => PresenterMethod.decode(
        const MethodCall('checklistToggle', {'slideIndex': 0, 'column': 1}),
      ),
      throwsFormatException,
    );
    expect(
      () => PresenterMethod.decode(
        const MethodCall('mediaComplete', {'index': 1, 'kind': 'unknown'}),
      ),
      throwsFormatException,
    );
  });

  test('accepts a legacy snapshot, an explicit clear and a ready signal', () {
    final update = AudienceMethod.decode(
      const MethodCall('update', {'index': 1}),
    )!;
    expect(update.method, AudienceMethod.update);
    expect(update.arguments, {'index': 1});
    expect(
      AudienceMethod.decode(
        const MethodCall('inkLive', {'index': 0, 'stroke': null}),
      )!.arguments,
      {'index': 0, 'stroke': null},
    );
    expect(
      PresenterMethod.decode(const MethodCall('ready'))!.arguments,
      isEmpty,
    );
  });

  test('each current method has a typed sender and an exhaustive receiver', () {
    final files = Directory('lib/widgets/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('audience_protocol.dart'));
    final source = files.map((file) => file.readAsStringSync()).join('\n');

    Set<String> methods(RegExp invocation) => {
      for (final match in invocation.allMatches(source)) match.group(1)!,
    };

    expect(methods(RegExp(r'\bAudienceMethod\.(\w+)\s*\.send\(')), {
      for (final method in AudienceMethod.values) method.name,
    });
    expect(
      {
        ...methods(RegExp(r'\bPresenterMethod\.(\w+)\s*\.send\(')),
        ...methods(RegExp(r'\b_send\(\s*PresenterMethod\.(\w+)')),
      },
      {
        for (final method in PresenterMethod.values)
          if (method != PresenterMethod.audioComplete) method.name,
      },
    );
    // The analyzer checks the enum switches for receiver exhaustiveness. A
    // channel invocation outside the protocol would bypass that contract.
    expect(
      RegExp(
        r'\b(audienceChannel|presenterChannel)\s*\.invokeMethod',
      ).hasMatch(source),
      isFalse,
    );
  });
}
