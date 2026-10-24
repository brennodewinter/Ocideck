// Guard for the libwebrtc log pin (#2535): the binding pins
// `Helper.setLogger` at [WebrtcMediaCore.webrtcLogSeverity]. A 'verbose' or
// 'info' level would put full SDP and ICE addresses into logs — the pin is a
// constant precisely so this test can watch it without constructing the
// (platform-channel) core in a VM test.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_media_core_webrtc.dart';

void main() {
  test('libwebrtc log level stays pinned at error', () {
    expect(WebrtcMediaCore.webrtcLogSeverity, 'error');
  });
}
