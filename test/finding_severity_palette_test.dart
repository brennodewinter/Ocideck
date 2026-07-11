import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/finding_severity_palette.dart';

void main() {
  group('FindingSeverityPalette', () {
    test('without a profile uses the built-in defaults', () {
      expect(
        FindingSeverityPalette.of(Cvss4Severity.critical),
        AppTheme.severityCritical,
      );
      expect(
        FindingSeverityPalette.of(Cvss4Severity.none),
        AppTheme.severityNone,
      );
      // An unset severity falls to the neutral band.
      expect(FindingSeverityPalette.of(null), AppTheme.severityNone);
    });

    test('a default profile matches the built-in defaults', () {
      const p = ThemeProfile();
      for (final s in Cvss4Severity.values) {
        expect(
          FindingSeverityPalette.of(s, profile: p),
          FindingSeverityPalette.of(s),
          reason: s.name,
        );
      }
    });

    test('reads the token colour from the profile', () {
      const p = ThemeProfile(severityCriticalColor: '#010203');
      expect(
        FindingSeverityPalette.of(Cvss4Severity.critical, profile: p),
        const Color(0xFF010203),
      );
      // Untouched bands keep their default colour.
      expect(
        FindingSeverityPalette.of(Cvss4Severity.low, profile: p),
        AppTheme.severityLow,
      );
    });

    test('a malformed token falls back to the default colour', () {
      const p = ThemeProfile(severityHighColor: 'not-a-color');
      expect(
        FindingSeverityPalette.of(Cvss4Severity.high, profile: p),
        AppTheme.severityHigh,
      );
    });
  });

  group('ThemeProfile severity tokens', () {
    test('toJson/fromJson preserves the tokens', () {
      const p = ThemeProfile(
        severityCriticalColor: '#111111',
        severityHighColor: '#222222',
        severityMediumColor: '#333333',
        severityLowColor: '#444444',
        severityNoneColor: '#555555',
      );
      final r = ThemeProfile.fromJson(p.toJson());
      expect(r.severityCriticalColor, '#111111');
      expect(r.severityHighColor, '#222222');
      expect(r.severityMediumColor, '#333333');
      expect(r.severityLowColor, '#444444');
      expect(r.severityNoneColor, '#555555');
    });

    test('fromJson rejects an injection payload and falls back', () {
      final r = ThemeProfile.fromJson({
        'severityCriticalColor': 'red}</style><script>',
      });
      expect(r.severityCriticalColor, '#B91C1C');
    });

    test('copyWith updates a single token, leaving the others', () {
      const p = ThemeProfile();
      final r = p.copyWith(severityMediumColor: '#ABCDEF');
      expect(r.severityMediumColor, '#ABCDEF');
      expect(r.severityLowColor, p.severityLowColor);
    });

    test(
      'the built-in Security profile ships the default severity palette',
      () {
        const p = ThemeProfile.security;
        expect(p.name, 'Security');
        for (final s in Cvss4Severity.values) {
          expect(
            FindingSeverityPalette.of(s, profile: p),
            FindingSeverityPalette.of(s),
            reason: s.name,
          );
        }
      },
    );
  });
}
