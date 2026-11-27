import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ociserve/ociserve_intake_web_routes.dart';

void main() {
  final base = Uri.parse('https://serve.example.org/deployment');
  final intake = '${base.toString()}/api/v1/intake';

  test('allows each respondent endpoint on the invitation server', () {
    for (final (method, path) in [
      ('GET', 'forms/form-ref'),
      ('POST', 'challenges'),
      ('POST', 'challenges/challenge-id/verify'),
      ('GET', 'submissions/one'),
      ('PUT', 'submissions/one/draft'),
      ('POST', 'submissions/one/submit'),
      ('POST', 'submissions/one/withdraw'),
    ]) {
      expect(
        isIntakeWebRequest(base, method, Uri.parse('$intake/$path')),
        true,
      );
    }
  });

  test('refuses other origins, paths and methods', () {
    for (final (method, url) in [
      ('GET', 'https://other.example.org/deployment/api/v1/intake/forms/f'),
      (
        'GET',
        'https://serve.example.org:8443/deployment/api/v1/intake/forms/f',
      ),
      ('GET', '${base.toString()}/api/v1/me'),
      ('GET', '$intake/forms/f?key=one'),
      ('GET', '$intake/forms/f#local'),
      ('GET', '$intake/forms/one%2Ftwo'),
      ('POST', '$intake/forms/f'),
      ('PUT', '$intake/submissions/one/withdraw'),
      ('POST', '$intake/submissions/one/unlisted'),
    ]) {
      expect(isIntakeWebRequest(base, method, Uri.parse(url)), false);
    }
  });
}
