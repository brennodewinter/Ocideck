import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/net_guard.dart';

/// Behavioural tests for [NetGuard.isBlockedAddress] / [NetGuard.isBlockedHost].
/// The IPv4-in-IPv6 cases are the regression guards: Dart reports
/// `::ffff:127.0.0.1` as an IPv6 address whose `isLoopback` is false, so before
/// the fix an embedded internal IPv4 slipped through the SSRF gate.
void main() {
  group('isBlockedAddress — native IPv4', () {
    for (final ip in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '169.254.169.254', // link-local / cloud metadata
      '100.64.0.1', // CGNAT
      '0.0.0.0',
    ]) {
      test('blocks $ip', () {
        expect(NetGuard.isBlockedAddress(InternetAddress(ip)), isTrue);
      });
    }

    for (final ip in ['8.8.8.8', '1.1.1.1', '93.184.216.34', '172.32.0.1']) {
      test('allows public $ip', () {
        expect(NetGuard.isBlockedAddress(InternetAddress(ip)), isFalse);
      });
    }
  });

  group('isBlockedAddress — IPv4-mapped / -compatible / NAT64 IPv6', () {
    for (final ip in [
      '::ffff:127.0.0.1', // mapped loopback
      '::ffff:169.254.169.254', // mapped cloud metadata
      '::ffff:10.0.0.5', // mapped RFC1918
      '::ffff:192.168.1.1',
      '64:ff9b::7f00:1', // NAT64 of 127.0.0.1
      '64:ff9b::a9fe:a9fe', // NAT64 of 169.254.169.254
      '::', // unspecified
      '::1', // loopback
    ]) {
      test('blocks $ip', () {
        final addr = InternetAddress.tryParse(ip);
        expect(addr, isNotNull, reason: '$ip should parse');
        expect(NetGuard.isBlockedAddress(addr!), isTrue);
      });
    }

    for (final ip in ['::ffff:8.8.8.8', '64:ff9b::808:808', '2001:4860:4860::8888']) {
      test('allows public-mapped $ip', () {
        final addr = InternetAddress.tryParse(ip)!;
        expect(NetGuard.isBlockedAddress(addr), isFalse);
      });
    }

    test('blocks fc00::/7 unique-local', () {
      expect(NetGuard.isBlockedAddress(InternetAddress.tryParse('fd12::1')!), isTrue);
    });
  });

  group('isAllowedMediaUrl — literal bracketed IPv6 host', () {
    for (final url in [
      'http://[::ffff:127.0.0.1]/x',
      'http://[::ffff:169.254.169.254]/latest/meta-data/',
      'http://[64:ff9b::a9fe:a9fe]/x',
    ]) {
      test('rejects $url', () {
        expect(NetGuard.isAllowedMediaUrl(url), isFalse);
      });
    }

    test('allows a public mapped host', () {
      expect(NetGuard.isAllowedMediaUrl('http://[::ffff:8.8.8.8]/x'), isTrue);
    });
  });
}
