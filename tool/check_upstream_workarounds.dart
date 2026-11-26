// Reviews Flutter workarounds at the toolchain gate (#3219). A closed issue
// requests a release/reproduction check; it never authorizes automatic removal.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const workaroundRegister = 'tool/upstream_workarounds.json';

class UpstreamIssue {
  final int number;
  final String state;

  UpstreamIssue(this.number, this.state);

  String get url => 'https://github.com/flutter/flutter/issues/$number';
}

class Workaround {
  final String id;
  final String reviewedFlutter;
  final String decision;
  final String verification;
  final List<String> pins;
  final List<UpstreamIssue> upstream;

  Workaround(Map<String, dynamic> row)
    : id = _text(row, 'id'),
      reviewedFlutter = _version(row, 'reviewed_flutter'),
      decision = _text(row, 'decision'),
      verification = _text(row, 'verification'),
      pins = _pins(row),
      upstream = _issues(row) {
    _version(row, 'observed_flutter');
    if (row['issue'] is! int || (row['issue'] as int) <= 0) {
      throw const FormatException('Missing local issue number');
    }
    final date = _text(row, 'reviewed_at');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().split('T').first != date) {
      throw const FormatException('Invalid review date');
    }
  }
}

String _text(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key');
  }
  return value;
}

String _version(Map<String, dynamic> row, String key) {
  final value = _text(row, key);
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) {
    throw FormatException('Invalid $key');
  }
  return value;
}

List<String> _pins(Map<String, dynamic> row) {
  final pins = row['pins'];
  if (pins is! List || pins.isEmpty) {
    throw const FormatException('Missing workaround pins');
  }
  return pins.map((p) {
    if (p is! String ||
        p.isEmpty ||
        p.startsWith('/') ||
        p.contains('..') ||
        p.contains('\\')) {
      throw const FormatException('Invalid pin path');
    }
    return p;
  }).toList();
}

List<UpstreamIssue> _issues(Map<String, dynamic> row) {
  final issues = row['upstream'];
  if (issues is! List || issues.isEmpty) {
    throw const FormatException('Missing upstream issues');
  }
  return issues.map((entry) {
    if (entry is! Map<String, dynamic> ||
        entry['number'] is! int ||
        (entry['number'] as int) <= 0 ||
        !['open', 'closed'].contains(entry['state'])) {
      throw const FormatException('Invalid upstream issue/state');
    }
    return UpstreamIssue(entry['number'] as int, entry['state'] as String);
  }).toList();
}

List<Workaround> parseWorkarounds(String source) {
  final data = jsonDecode(source);
  if (data is! Map<String, dynamic> ||
      data['schema_version'] != 1 ||
      data['workarounds'] is! List) {
    throw const FormatException('Invalid workaround register');
  }
  final rows = data['workarounds'] as List;
  if (rows.isEmpty || rows.any((row) => row is! Map<String, dynamic>)) {
    throw const FormatException('Empty or invalid workaround register');
  }
  final result = rows
      .map((row) => Workaround(row as Map<String, dynamic>))
      .toList();
  if (result.map((w) => w.id).toSet().length != result.length) {
    throw const FormatException('Duplicate workaround id');
  }
  return result;
}

/// Fetches public issue metadata only; no credentials or SDK writes are needed.
Future<String> fetchUpstreamState(int number) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    return await (() async {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/flutter/flutter/issues/$number'),
      );
      request.followRedirects = false;
      request.headers.set('User-Agent', 'OciDeck-upstream-workaround-review');
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('GitHub HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Oversized GitHub response');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map ||
          data['number'] != number ||
          !['open', 'closed'].contains(data['state'])) {
        throw const FormatException('Invalid GitHub issue response');
      }
      return data['state'] as String;
    })().timeout(const Duration(seconds: 8));
  } finally {
    client.close(force: true);
  }
}

/// Reports closure even from a saved snapshot, including when GitHub is down.
/// A new Flutter pin fails until each active workaround has been reviewed.
Future<bool> reviewWorkarounds(
  List<Workaround> workarounds,
  String pin, {
  Future<String> Function(int)? fetchState,
  required void Function(String) report,
}) async {
  final states = <int, String>{};
  final numbers = workarounds.expand((w) => w.upstream).map((i) => i.number);
  await Future.wait(
    numbers.toSet().map((number) async {
      if (fetchState == null) return;
      try {
        final state = await fetchState(number);
        if (!['open', 'closed'].contains(state)) {
          throw const FormatException('Invalid issue state');
        }
        states[number] = state;
      } on Exception catch (error) {
        report('UPSTREAM UNKNOWN #$number: $error — using recorded state.');
      }
    }),
  );
  var valid = true;
  for (final w in workarounds) {
    if (w.reviewedFlutter != pin) {
      valid = false;
      report(
        'UPSTREAM REVIEW REQUIRED ${w.id}: reviewed for '
        '${w.reviewedFlutter}, pin is $pin. Run: ${w.verification}',
      );
    }
    for (final issue in w.upstream) {
      final live = states[issue.number];
      if ((live ?? issue.state) != 'closed') continue;
      final changed = live == 'closed' && issue.state == 'open';
      report(
        'UPSTREAM CLOSED ${w.id}: ${issue.url}'
        '${changed ? ' (closed since recorded review)' : ''}'
        '${live == null ? ' (recorded; live status unavailable)' : ''}.\n'
        '  Retained at Flutter ${w.reviewedFlutter}: ${w.decision}\n'
        '  Verify before removal: ${w.verification}',
      );
    }
  }
  return valid;
}

Future<bool> checkUpstreamWorkarounds(
  String pin, {
  bool offline = false,
}) async {
  try {
    final workarounds = parseWorkarounds(
      File(workaroundRegister).readAsStringSync(),
    );
    for (final w in workarounds) {
      for (final path in w.pins) {
        if (!File(path).existsSync()) {
          throw FormatException('${w.id}: pin $path is missing');
        }
      }
    }
    if (offline) {
      stdout.writeln('Upstream review: offline, recorded states only.');
    }
    return await reviewWorkarounds(
      workarounds,
      pin,
      fetchState: offline ? null : fetchUpstreamState,
      report: stdout.writeln,
    );
  } on Exception catch (error) {
    stderr.writeln('Upstream workaround register FAILED: $error');
    return false;
  }
}
