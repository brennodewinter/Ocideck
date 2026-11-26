// Every persisted model field needs an executable, non-default roundtrip case.
// The inventory is read from the same typed case map the tests execute (#3217).
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const roundtripCasesPath = 'test/support/persistence_roundtrip_cases.dart';
const roundtripExclusions = <String, Map<String, String>>{
  'Slide': {
    'id':
        'Parse-time UUID; stable authored links use anchor instead. Tested as regenerated.',
    'mediaRedacted':
        'Transient privacy projection flag; source storage resets it. Tested explicitly.',
    'contentRedacted':
        'Transient privacy projection flag; source storage resets it. Tested explicitly.',
    'renderPage':
        'Render-only copy of an authored rich-text slide. Storage excludes the copy; tested with the authored slide present.',
  },
  'ThemeProfile': {},
};

// No uncovered fields were accepted when this gate landed. A ratchet at zero.
const roundtripDebt = <String>{};

CompilationUnit _parse(String source) => parseString(
  content: source,
  featureSet: FeatureSet.latestLanguageVersion(),
).unit;

Set<String> modelFields(String source, String model) {
  final visitor = _ModelFields(model);
  _parse(source).accept(visitor);
  if (!visitor.found || visitor.fields.isEmpty) {
    throw FormatException('$model has no readable instance fields');
  }
  return visitor.fields;
}

class _ModelFields extends RecursiveAstVisitor<void> {
  _ModelFields(this.model);
  final String model;
  final fields = <String>{};
  bool found = false;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.namePart.typeName.lexeme == model) found = true;
    super.visitClassDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic) return;
    final parent = node.thisOrAncestorOfType<ClassDeclaration>();
    if (parent?.namePart.typeName.lexeme == model) {
      fields.addAll(node.fields.variables.map((v) => v.name.lexeme));
    }
  }
}

/// Rejects stale/overlapping classifications as well as an unaccounted field.
List<String> roundtripParityProblems(
  Set<String> fields,
  Set<String> probes, {
  Map<String, String> exclusions = const {},
  Set<String> debt = roundtripDebt,
}) => [
  for (final field
      in fields
          .difference(probes)
          .difference(exclusions.keys.toSet())
          .difference(debt))
    '$field: no executable roundtrip case or documented exclusion',
  for (final field in {
    ...probes,
    ...exclusions.keys,
    ...debt,
  }.difference(fields))
    '$field: stale inventory entry, not a model field',
  for (final field in probes.intersection(exclusions.keys.toSet()))
    '$field: both persistent and deliberately excluded',
  for (final entry in exclusions.entries)
    if (entry.value.trim().isEmpty) '${entry.key}: exclusion needs a reason',
  if (debt.isNotEmpty)
    'The roundtrip debt ratchet is zero and may not grow: $debt',
];

Set<String> caseFields(String source, String mapName, String helper) {
  final visitor = _CaseMap(mapName, helper);
  _parse(source).accept(visitor);
  if (!visitor.found || visitor.fields.isEmpty) {
    throw FormatException('$mapName: missing or empty executable case map');
  }
  return visitor.fields;
}

class _CaseMap extends RecursiveAstVisitor<void> {
  _CaseMap(this.mapName, this.helper);
  final String mapName;
  final String helper;
  final fields = <String>{};
  bool found = false;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme != mapName) return;
    found = true;
    final map = node.initializer;
    if (map is! SetOrMapLiteral) {
      throw FormatException('$mapName must be a literal map');
    }
    for (final entry in map.elements) {
      if (entry is! MapLiteralEntry || entry.key is! SimpleStringLiteral) {
        throw FormatException(
          '$mapName: computed/spread cases are not accountable',
        );
      }
      final field = (entry.key as SimpleStringLiteral).value;
      if (!fields.add(field)) {
        throw FormatException('$mapName: duplicate $field');
      }
      final value = entry.value;
      if (value is! MethodInvocation || value.methodName.name != helper) {
        throw FormatException(
          '$field: use $helper with a fixture and property reader',
        );
      }
      final args = value.argumentList.arguments
          .map((a) => a.argumentExpression)
          .toList();
      if (args.length != (helper == 'slideCase' ? 3 : 2)) {
        throw FormatException('$field: wrong case arguments');
      }
      final read = args.last;
      if (read is! FunctionExpression || read.body is! ExpressionFunctionBody) {
        throw FormatException('$field: needs an actual property reader');
      }
      final getter = (read.body as ExpressionFunctionBody).expression
          .toSource();
      final match = RegExp(
        r'^s\.(\w+)(?:(?:\?|!)?\.(?:toJson|toComments)\(\))?$',
      ).firstMatch(getter);
      if (match?.group(1) != field) {
        throw FormatException('$field: reader reads $getter');
      }
      final change = args[args.length - 2];
      if (change is! FunctionExpression ||
          change.body is! ExpressionFunctionBody) {
        throw FormatException('$field: needs a non-default copyWith fixture');
      }
      final expression = (change.body as ExpressionFunctionBody).expression;
      if (expression is! MethodInvocation ||
          expression.methodName.name != 'copyWith' ||
          !expression.argumentList.arguments.whereType<NamedArgument>().any(
            (a) => a.name.lexeme == field,
          )) {
        throw FormatException('$field: fixture does not set this field');
      }
    }
  }
}

void main() {
  try {
    final source = File(roundtripCasesPath).readAsStringSync();
    var failures = 0;
    for (final spec in [
      ('Slide', 'lib/models/slide.dart', 'slideRoundtripCases', 'slideCase'),
      (
        'ThemeProfile',
        'lib/models/settings.dart',
        'themeRoundtripCases',
        'themeCase',
      ),
    ]) {
      final fields = modelFields(File(spec.$2).readAsStringSync(), spec.$1);
      final probes = caseFields(source, spec.$3, spec.$4);
      final excluded = roundtripExclusions[spec.$1]!;
      final problems = roundtripParityProblems(
        fields,
        probes,
        exclusions: excluded,
      );
      for (final problem in problems) {
        stderr.writeln('${spec.$1}.$problem');
      }
      failures += problems.length;
      stdout.writeln(
        '${spec.$1}: ${fields.length} fields, ${probes.length} executable cases, ${excluded.length} explained exclusions, ${roundtripDebt.length} debt.',
      );
    }
    if (failures != 0) exitCode = 1;
  } on Exception catch (error) {
    stderr.writeln('check-roundtrip-field-parity FAILED: $error');
    exitCode = 1;
  }
}
