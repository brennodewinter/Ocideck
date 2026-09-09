import 'package:flutter_test/flutter_test.dart';

import 'package:ocideck/models/ociserve_evidence.dart';

void main() {
  group('EvidenceUpload', () {
    test('parses a clean upload from JSON', () {
      final upload = EvidenceUpload.fromJson({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'participant_id': '660e8400-e29b-41d4-a716-446655440000',
        'filename': 'bhv-certificaat.pdf',
        'declared_type': 'application/pdf',
        'declared_size': 102400,
        'declared_hash': 'abc123',
        'blob_hash': 'def456',
        'blob_size': 102400,
        'status': 'clean',
        'created_at': '2026-09-01T10:00:00Z',
        'completed_at': '2026-09-01T10:01:00Z',
        'verified_at': '2026-09-01T10:02:00Z',
      });
      expect(upload.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(upload.filename, 'bhv-certificaat.pdf');
      expect(upload.status, EvidenceUploadStatus.clean);
      expect(upload.isClean, isTrue);
      expect(upload.isInProgress, isFalse);
      expect(upload.declaredSize, 102400);
      expect(upload.completedAt, isNotNull);
      expect(upload.verifiedAt, isNotNull);
    });

    test('parses a pending upload with minimal fields', () {
      final upload = EvidenceUpload.fromJson({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'filename': 'scan.jpg',
        'declared_type': 'image/jpeg',
        'declared_size': 51200,
        'declared_hash': 'abc123',
        'status': 'pending',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(upload.status, EvidenceUploadStatus.pending);
      expect(upload.isClean, isFalse);
      expect(upload.isInProgress, isTrue);
      expect(upload.participantId, isEmpty);
      expect(upload.blobHash, isEmpty);
      expect(upload.completedAt, isNull);
    });

    test('parses a rejected upload with reason', () {
      final upload = EvidenceUpload.fromJson({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'filename': 'doc.pdf',
        'declared_type': 'application/pdf',
        'declared_size': 100,
        'declared_hash': 'abc',
        'status': 'rejected',
        'rejection_reason': 'File is not a valid PDF',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(upload.status, EvidenceUploadStatus.rejected);
      expect(upload.rejectionReason, 'File is not a valid PDF');
    });

    test('throws on missing id', () {
      expect(
        () => EvidenceUpload.fromJson({
          'filename': 'doc.pdf',
          'declared_type': 'application/pdf',
          'declared_size': 100,
          'declared_hash': 'abc',
          'status': 'pending',
          'created_at': '2026-09-01T10:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('handles unknown status gracefully', () {
      final upload = EvidenceUpload.fromJson({
        'id': 'test-id',
        'filename': 'f',
        'declared_type': 'image/png',
        'declared_size': 0,
        'declared_hash': 'h',
        'status': 'unknown_status',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(upload.status, EvidenceUploadStatus.pending);
    });
  });

  group('EvidenceUploadRequest', () {
    test('serializes to JSON without participant_id', () {
      const request = EvidenceUploadRequest(
        filename: 'cert.pdf',
        declaredType: 'application/pdf',
        declaredSize: 1024,
        declaredHash: 'sha256',
      );
      final json = request.toJson();
      expect(json['filename'], 'cert.pdf');
      expect(json['declared_type'], 'application/pdf');
      expect(json['declared_size'], 1024);
      expect(json['declared_hash'], 'sha256');
      expect(json.containsKey('participant_id'), isFalse);
    });

    test('serializes to JSON with participant_id', () {
      const request = EvidenceUploadRequest(
        filename: 'cert.pdf',
        declaredType: 'application/pdf',
        declaredSize: 1024,
        declaredHash: 'sha256',
        participantId: 'part-123',
      );
      final json = request.toJson();
      expect(json['participant_id'], 'part-123');
    });
  });

  group('OciServeQualification', () {
    test('parses an approved qualification with expiry', () {
      final qual = OciServeQualification.fromJson({
        'id': 'qual-1',
        'participant_id': 'part-1',
        'skill_version_id': 'skill-v1',
        'status': 'approved',
        'issued_by': 'admin-1',
        'issued_at': '2026-01-15T10:00:00Z',
        'expires_at': '2028-01-15T10:00:00Z',
        'snapshot': {
          'title': 'Bedrijfshulpverlener',
          'validity_months': 24,
        },
        'created_at': '2026-01-15T10:00:00Z',
      });
      expect(qual.id, 'qual-1');
      expect(qual.status, QualificationStatus.approved);
      expect(qual.isActive, isTrue);
      expect(qual.skillTitle, 'Bedrijfshulpverlener');
      expect(qual.validityMonths, 24);
      expect(qual.expiresAt, isNotNull);
    });

    test('parses an expired qualification', () {
      final qual = OciServeQualification.fromJson({
        'id': 'qual-2',
        'participant_id': 'part-1',
        'skill_version_id': 'skill-v2',
        'status': 'expired',
        'issued_by': 'admin-1',
        'issued_at': '2020-01-15T10:00:00Z',
        'expires_at': '2022-01-15T10:00:00Z',
        'snapshot': {'title': 'EHBO'},
        'created_at': '2020-01-15T10:00:00Z',
      });
      expect(qual.status, QualificationStatus.expired);
      expect(qual.isActive, isFalse);
    });

    test('parses a pending qualification without expiry', () {
      final qual = OciServeQualification.fromJson({
        'id': 'qual-3',
        'participant_id': 'part-1',
        'skill_version_id': 'skill-v3',
        'status': 'pending',
        'issued_by': 'admin-1',
        'issued_at': '2026-09-01T10:00:00Z',
        'snapshot': {},
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(qual.status, QualificationStatus.pending);
      expect(qual.isActive, isFalse);
      expect(qual.expiresAt, isNull);
      expect(qual.skillTitle, isEmpty);
    });

    test('throws on missing id', () {
      expect(
        () => OciServeQualification.fromJson({
          'participant_id': 'p',
          'skill_version_id': 's',
          'status': 'approved',
          'issued_by': 'a',
          'issued_at': '2026-01-01T00:00:00Z',
          'snapshot': {},
          'created_at': '2026-01-01T00:00:00Z',
        }),
        throwsFormatException,
      );
    });
  });

  group('OciServeSkillDefinition', () {
    test('parses a skill with requirements', () {
      final skill = OciServeSkillDefinition.fromJson({
        'description': 'BHV certification',
        'badge_class_url': 'https://badges.example.nl/bhv',
        'validity_months': 24,
        'requirements': [
          {'course_id': 'course-1', 'title': 'BHV Basis'},
          {'course_id': 'course-2', 'title': 'BHV Herhaling'},
        ],
        'published_at': '2026-01-01T00:00:00Z',
        'created_at': '2025-12-01T00:00:00Z',
      });
      expect(skill.description, 'BHV certification');
      expect(skill.badgeClassUrl, isNotNull);
      expect(skill.badgeClassUrl!.toString(), 'https://badges.example.nl/bhv');
      expect(skill.validityMonths, 24);
      expect(skill.requirements.length, 2);
      expect(skill.requirements[0].courseId, 'course-1');
      expect(skill.requirements[0].title, 'BHV Basis');
      expect(skill.requirements[1].title, 'BHV Herhaling');
    });

    test('parses a skill with no requirements', () {
      final skill = OciServeSkillDefinition.fromJson({
        'description': 'Simple skill',
      });
      expect(skill.requirements, isEmpty);
      expect(skill.validityMonths, 0);
      expect(skill.badgeClassUrl?.hasAuthority, isFalse);
    });
  });

  group('EvidenceUploadStatus', () {
    test('all statuses parse correctly', () {
      expect(EvidenceUploadStatus.fromString('pending'),
          EvidenceUploadStatus.pending);
      expect(EvidenceUploadStatus.fromString('uploaded'),
          EvidenceUploadStatus.uploaded);
      expect(EvidenceUploadStatus.fromString('clean'),
          EvidenceUploadStatus.clean);
      expect(EvidenceUploadStatus.fromString('rejected'),
          EvidenceUploadStatus.rejected);
      expect(EvidenceUploadStatus.fromString('failed'),
          EvidenceUploadStatus.failed);
    });
  });

  group('QualificationStatus', () {
    test('all statuses parse correctly', () {
      expect(QualificationStatus.fromString('pending'),
          QualificationStatus.pending);
      expect(QualificationStatus.fromString('approved'),
          QualificationStatus.approved);
      expect(QualificationStatus.fromString('rejected'),
          QualificationStatus.rejected);
      expect(QualificationStatus.fromString('revoked'),
          QualificationStatus.revoked);
      expect(QualificationStatus.fromString('expired'),
          QualificationStatus.expired);
    });
  });
}
