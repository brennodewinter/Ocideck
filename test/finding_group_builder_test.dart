import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_group_builder.dart';

void main() {
  const spec = FindingSpec(
    heading: 'F-03 · SQL injection in the login form',
    scopeObject: 'https://app.example/login',
    cvssVector:
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
    cweId: 89,
    cweName: 'SQL Injection',
    description: 'x',
  );

  group('buildFindingGroup', () {
    test('default group is a finding header plus an evidence placeholder', () {
      final group = buildFindingGroup(spec: spec, findingId: 'F-03');
      expect(group, hasLength(2));

      final header = group.first;
      expect(header.type, SlideType.finding);
      expect(header.findingRole, FindingRole.header);
      expect(header.findingId, 'F-03');
      expect(header.title, spec.heading);

      final evidence = group.last;
      expect(evidence.type, SlideType.image);
      expect(evidence.findingRole, FindingRole.evidence);
      expect(evidence.findingId, 'F-03');
    });

    test('the header round-trips the spec (id/role stay slide-level)', () {
      final header = buildFindingGroup(spec: spec, findingId: 'F-03').first;
      final parsed = FindingSpec.parse(header.customMarkdown);
      expect(parsed.heading, spec.heading);
      expect(parsed.cweId, 89);
      expect(parsed.cvssVector, spec.cvssVector);
      // Severity is derived from the vector, so the header carries a real band.
      expect(parsed.severity, isNotNull);
    });

    test(
      'addDetail inserts a bullets detail slide between header and evidence',
      () {
        final group = buildFindingGroup(
          spec: spec,
          findingId: 'F-03',
          addDetail: true,
        );
        expect(group.map((s) => s.type), [
          SlideType.finding,
          SlideType.bullets,
          SlideType.image,
        ]);
        expect(group.map((s) => s.findingRole), [
          FindingRole.header,
          FindingRole.detail,
          FindingRole.evidence,
        ]);
      },
    );

    test('addEvidence:false yields just the header', () {
      final group = buildFindingGroup(
        spec: spec,
        findingId: 'F-03',
        addEvidence: false,
      );
      expect(group, hasLength(1));
      expect(group.single.type, SlideType.finding);
    });

    test('every member shares the one finding id', () {
      final group = buildFindingGroup(
        spec: spec,
        findingId: 'F-99',
        addDetail: true,
      );
      expect(group.every((s) => s.findingId == 'F-99'), isTrue);
    });
  });
}
