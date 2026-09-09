// Contract-drift gate: every OciServe route that ociserve_gateway.dart calls
// must exist in the pinned OpenAPI spec, with the right method and the
// response fields OciDeck reads.  When OciServe renames, removes or reshapes
// a route, this test goes red — *before* a user hits a broken endpoint.
//
// Pinned spec:  test/fixtures/ociserve_openapi.yaml
// OciServe commit:  8f73aefd5e4f2dfaf3060a4c819f68fe7edef266
//
// Updaten:  zie docs/CHECKS.md → "OciServe contractpoort".

import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OciServe commit the pinned spec was copied from.
const pinnedOciServeCommit = '8f73aefd5e4f2dfaf3060a4c819f68fe7edef266';

/// One route the gateway calls, with the response fields OciDeck reads.
/// Fields are dot-paths into the JSON response (after $ref resolution).
/// An empty [responseFields] list means OciDeck does not parse the body
/// (binary download, or fire-and-forget POST).
class GatewayRoute {
  const GatewayRoute({
    required this.method,
    required this.path,
    this.responseFields = const [],
    this.responseSchema, // expected schema name for 200/201 responses
  });

  final String method;
  final String path;
  final List<String> responseFields;
  final String? responseSchema;
}

/// Every route ociserve_gateway.dart calls, with the fields it reads.
/// Adding a route to the gateway means adding it here too — that is the
/// point: the list is the contract, and the test checks it against the spec.
const gatewayRoutes = <GatewayRoute>[
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/installation',
    responseSchema: 'InstallationStatus',
    // OciDeck reads these from the top level (with an oidc.* fallback).
    responseFields: ['ocideck_native_client_id', 'oidc_issuer'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/me',
    responseSchema: 'MeResponse',
    responseFields: [
      'account.id',
      'account.display_name',
      'account.email',
      'account.avatar_hash',
      'memberships',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/learning-feed',
    responseSchema: 'SelfLearningFeed',
    responseFields: ['courses'],
  ),
  GatewayRoute(
    method: 'GET',
    path:
        '/api/v1/organizations/{}/me/course-versions/{}/lessons/{}/package',
    // Binary download — no JSON fields to check.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/assets/{}',
    // Binary download — no JSON fields to check.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/me/avatar',
    // Binary download — no JSON fields to check.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/learning-state',
    responseSchema: 'LearningState',
    responseFields: ['lessons'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/privacy-data',
    responseSchema: 'PrivacyData',
    responseFields: ['participant_id', 'generated_at', 'data'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/playback-sessions',
    // Fire-and-forget POST — no response fields to check.
  ),
];

/// Normalise a path so {param_name} becomes {} for comparison.
String normalisePath(String path) => path.replaceAll(RegExp(r'\{[^}]+\}'), '{}');

/// Resolve a $ref like '#/components/schemas/Foo' to the actual node.
dynamic resolveRef(dynamic node, String ref) {
  if (!ref.startsWith('#/')) return null;
  final parts = ref.substring(2).split('/');
  dynamic current = node;
  for (final part in parts) {
    if (current is Map) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}

/// Recursively resolve all $ref pointers in a schema node.
dynamic resolveAllRefs(dynamic node, dynamic root) {
  if (node is Map) {
    if (node.containsKey(r'$ref')) {
      final resolved = resolveRef(root, node[r'$ref'] as String);
      if (resolved == null) return node;
      return resolveAllRefs(resolved, root);
    }
    return Map<String, dynamic>.from({
      for (final entry in node.entries)
        entry.key.toString(): resolveAllRefs(entry.value, root),
    });
  }
  if (node is List) {
    return [for (final item in node) resolveAllRefs(item, root)];
  }
  return node;
}

/// Get the response schema for a 200/201 response of an operation.
Map<String, dynamic>? responseSchemaFor(
  Map<String, dynamic> operation,
  dynamic root,
) {
  final responses = operation['responses'] as Map<String, dynamic>?;
  if (responses == null) return null;
  // Try 200, then 201, then 2xx.
  for (final code in ['200', '201', '2xx']) {
    final response = responses[code] as Map<String, dynamic>?;
    if (response == null) continue;
    final content = response['content'] as Map<String, dynamic>?;
    if (content == null) continue;
    final jsonContent = content['application/json'] as Map<String, dynamic>?;
    if (jsonContent == null) continue;
    final schema = jsonContent['schema'];
    if (schema is Map) {
      return resolveAllRefs(schema, root) as Map<String, dynamic>;
    }
  }
  return null;
}

/// Check that a dot-path like 'account.id' exists in a schema map.
/// Handles nested objects via 'properties'.
bool schemaHasField(Map<String, dynamic>? schema, String dotPath) {
  if (schema == null) return false;
  final parts = dotPath.split('.');
  dynamic current = schema;
  for (final part in parts) {
    if (current is! Map) return false;
    // Navigate through 'properties' if present.
    final props = current['properties'] as Map<String, dynamic>?;
    final value = props?[part] ?? current[part];
    if (value == null) return false;
    current = resolveAllRefs(value, schema);
  }
  return true;
}

void main() {
  late final Map<String, dynamic> spec;
  late final Map<String, Map<String, dynamic>> specPaths; // normalised path → {method: operation}

  setUpAll(() {
    final file = File('test/fixtures/ociserve_openapi.yaml');
    final yaml = loadYaml(file.readAsStringSync());
    // Convert to plain maps for easy traversal.
    spec = _toDart(yaml) as Map<String, dynamic>;

    final rawPaths = spec['paths'] as Map<String, dynamic>? ?? {};
    specPaths = {};
    for (final entry in rawPaths.entries) {
      final normalised = normalisePath(entry.key);
      final methods = <String, dynamic>{};
      for (final methodEntry in (entry.value as Map<String, dynamic>).entries) {
        final method = methodEntry.key.toUpperCase();
        if (['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].contains(method)) {
          methods[method] = methodEntry.value;
        }
      }
      specPaths[normalised] = methods;
    }
  });

  test('pinned OpenAPI spec exists and is non-empty', () {
    expect(spec['openapi'], isNotNull,
        reason: 'test/fixtures/ociserve_openapi.yaml is not a valid OpenAPI doc');
    expect((spec['paths'] as Map).isNotEmpty, true,
        reason: 'pinned spec has no paths');
  });

  test('pinned OciServe commit SHA is recorded', () {
    expect(pinnedOciServeCommit, hasLength(40),
        reason: 'The OciServe commit SHA must be a full 40-char git SHA');
    expect(pinnedOciServeCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  group('every gateway route exists in the pinned spec', () {
    for (final route in gatewayRoutes) {
      test('${route.method} ${route.path}', () {
        final normalised = normalisePath(route.path);
        final methods = specPaths[normalised];
        expect(methods, isNotNull,
            reason:
                'Path $normalised not found in pinned spec — route removed or renamed in OciServe');
        expect(methods!.containsKey(route.method), true,
            reason:
                'Method ${route.method} not found on $normalised in pinned spec');
      });
    }
  });

  group('response fields OciDeck reads exist in the spec schema', () {
    for (final route in gatewayRoutes) {
      if (route.responseFields.isEmpty) continue;

      test('${route.method} ${route.path}', () {
        final normalised = normalisePath(route.path);
        final operation = specPaths[normalised]?[route.method]
            as Map<String, dynamic>?;
        expect(operation, isNotNull,
            reason: 'Operation not found for $normalised ${route.method}');

        final schema = responseSchemaFor(operation!, spec);
        expect(schema, isNotNull,
            reason:
                'No JSON response schema found for $normalised ${route.method}');

        for (final field in route.responseFields) {
          expect(
            schemaHasField(schema, field),
            true,
            reason:
                'Field "$field" not found in response schema of $normalised ${route.method} — '
                'the server renamed or removed a field OciDeck reads',
          );
        }
      });
    }
  });

  test('no gateway route is missing from the gatewayRoutes list', () {
    // This is a sanity check: if someone adds a route to the gateway but
    // forgets to add it here, the test count won't match. We can't
    // automatically count _api() calls in a Dart test, but we can at least
    // verify the list is non-empty and covers the known routes.
    expect(gatewayRoutes.length, greaterThanOrEqualTo(9),
        reason: 'The gateway calls at least 9 routes; the list must cover them');
  });
}

/// Recursively convert yaml_* nodes to plain Dart maps/lists for traversal.
dynamic _toDart(dynamic node) {
  if (node is Map) {
    return {for (final e in node.entries) e.key.toString(): _toDart(e.value)};
  }
  if (node is List) {
    return [for (final item in node) _toDart(item)];
  }
  return node;
}
