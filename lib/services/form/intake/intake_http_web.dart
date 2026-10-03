import 'intake_http.dart';

IntakeHttp createIntakeHttp() => const WebRefusingIntakeHttp();

/// Het web praat nog niet met een inzendserver: de webinvuller moet eerst kunnen verzegelen
/// (de age-bibliotheek draait niet onder dart2js, FORM_INTAKE.md §5.6), en `NetGuard` bestaat
/// daar niet.
class WebRefusingIntakeHttp implements IntakeHttp {
  const WebRefusingIntakeHttp();

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) async => throw const IntakeHttpException(IntakeHttpFailure.desktopOnly);
}
