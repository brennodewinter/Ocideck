import 'dart:io' show Platform;

bool get isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
