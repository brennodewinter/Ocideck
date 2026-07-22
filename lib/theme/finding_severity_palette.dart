import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../services/cvss/cvss4.dart';
import 'app_theme.dart';

/// Severity → colour tokens for finding cards and CVSS badges, following the
/// FIRST rating bands (PENTEST_MIAUW §11). When a [ThemeProfile] is given, the
/// band colours come from its severity tokens (so the built-in security profile
/// or a user-tuned deck restyles findings); otherwise the deterministic `const`
/// [AppTheme] tokens are used. Every token resolves through [AppTheme.parseHexColor]
/// with the `const` default as fallback, so a finding renders identically in the
/// on-screen preview and in a headless export isolate.
abstract final class FindingSeverityPalette {
  /// The band colour for [severity] (the neutral tone for an unset/absent one),
  /// read from [profile]'s severity tokens when supplied, else the built-in
  /// defaults.
  static Color of(Cvss4Severity? severity, {ThemeProfile? profile}) =>
      switch (severity ?? Cvss4Severity.none) {
        Cvss4Severity.critical =>
          profile == null
              ? AppTheme.severityCritical
              : AppTheme.parseHexColor(
                  profile.severityCriticalColor,
                  fallback: AppTheme.severityCritical,
                ),
        Cvss4Severity.high =>
          profile == null
              ? AppTheme.severityHigh
              : AppTheme.parseHexColor(
                  profile.severityHighColor,
                  fallback: AppTheme.severityHigh,
                ),
        Cvss4Severity.medium =>
          profile == null
              ? AppTheme.severityMedium
              : AppTheme.parseHexColor(
                  profile.severityMediumColor,
                  fallback: AppTheme.severityMedium,
                ),
        Cvss4Severity.low =>
          profile == null
              ? AppTheme.severityLow
              : AppTheme.parseHexColor(
                  profile.severityLowColor,
                  fallback: AppTheme.severityLow,
                ),
        Cvss4Severity.none =>
          profile == null
              ? AppTheme.severityNone
              : AppTheme.parseHexColor(
                  profile.severityNoneColor,
                  fallback: AppTheme.severityNone,
                ),
      };
}
