final _intakeIdentifier = RegExp(r'^[A-Za-z0-9_-]+$');

/// A browser invitation authorizes reaching this server's respondent API.
/// Its grants must stay on this connection and never reach the account API.
bool isIntakeWebRequest(Uri base, String method, Uri url) {
  if (base.scheme != 'https' ||
      url.scheme != 'https' ||
      base.host.isEmpty ||
      url.host.isEmpty ||
      base.origin != url.origin ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    return false;
  }
  final prefix = [
    ...base.pathSegments.where((part) => part.isNotEmpty),
    'api',
    'v1',
    'intake',
  ];
  final path = url.pathSegments;
  if (path.length <= prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (path[index] != prefix[index]) return false;
  }
  final route = path.sublist(prefix.length);
  if (url.hasQuery &&
      !(route.length == 1 &&
          route.first == 'own' &&
          url.queryParameters.keys.every((name) => name == 'cursor')))
    return false;
  if (route.length > 1 && !_intakeIdentifier.hasMatch(route[1])) return false;
  return switch (route) {
    ['forms', _] => method == 'GET',
    ['own'] || ['own', _] || ['own', _, 'content'] => method == 'GET',
    ['own', _, 'revision-grant'] => method == 'POST',

    ['challenges'] || ['challenges', _, 'verify'] => method == 'POST',
    ['submissions', _] => method == 'GET',
    ['submissions', _, 'draft'] => method == 'PUT',
    ['submissions', _, 'submit' || 'withdraw'] => method == 'POST',
    _ => false,
  };
}
