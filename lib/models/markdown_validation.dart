enum MarkdownValidationSeverity { error, warning, informational }

class MarkdownValidationIssue {
  final int line;
  final MarkdownValidationSeverity severity;
  final String message;

  /// Stable machine-readable code for callers that localize the finding.
  /// Generic Markdown validation keeps using [message] directly.
  final String? code;

  const MarkdownValidationIssue({
    required this.line,
    required this.severity,
    this.message = '',
    this.code,
  });

  @override
  String toString() => 'L$line: ${code ?? message}';
}

class MarkdownValidationResult {
  final List<MarkdownValidationIssue> issues;

  const MarkdownValidationResult(this.issues);

  bool get isValid => !issues.any(
    (issue) => issue.severity == MarkdownValidationSeverity.error,
  );

  bool get hasIssues => issues.isNotEmpty;

  int get errorCount => issues
      .where((i) => i.severity == MarkdownValidationSeverity.error)
      .length;

  int get warningCount => issues
      .where((i) => i.severity == MarkdownValidationSeverity.warning)
      .length;
}
