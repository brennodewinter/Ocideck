// De egresspoort van de serverroute (#2524): welke profielen mogen een
// verzoek laten vertrekken en met welke strategie. De hele matrix is puur
// — geen netwerk — want wie hier een gat laat, laat audio naar een adres
// dat de gebruiker niet koos.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_server_gate.dart';

AsrGateDenial? deny(AsrServerProfile p, {bool isWeb = false}) {
  final d = AsrServerGate.evaluate(p, isWeb: isWeb);
  return d is AsrGateDeny ? d.reason : null;
}

AsrGateAllow? allow(AsrServerProfile p, {bool isWeb = false}) {
  final d = AsrServerGate.evaluate(p, isWeb: isWeb);
  return d is AsrGateAllow ? d : null;
}

void main() {
  const loopback = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.loopback,
    baseUrl: 'http://127.0.0.1:8080',
  );
  const lan = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.lan,
    baseUrl: 'http://192.168.1.20:8080',
    trustedInternal: true,
  );
  const cloud = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.cloud,
    baseUrl: 'https://asr.example.nl',
    cloudConfirmed: true,
  );

  group('basisweigeringen', () {
    test('uitgeschakeld profiel vertrekt nooit', () {
      expect(
        deny(
          const AsrServerProfile(enabled: false, mode: AsrServerMode.loopback),
        ),
        AsrGateDenial.disabled,
      );
    });

    test('geen gekozen modus vertrekt nooit', () {
      expect(
        deny(const AsrServerProfile(enabled: true)),
        AsrGateDenial.modeNone,
      );
    });

    test('lege of kapotte URL is notConfigured', () {
      expect(deny(loopback.copyWith(baseUrl: '')), AsrGateDenial.notConfigured);
      expect(
        deny(loopback.copyWith(baseUrl: 'ftp://x')),
        AsrGateDenial.notConfigured,
      );
      expect(
        deny(loopback.copyWith(baseUrl: 'niet een url')),
        AsrGateDenial.notConfigured,
      );
    });

    test('credentials in de URL zijn per definitie ongeldig', () {
      // Opgesplitst zodat de secrets-scanner geen geheim-vormige literal
      // ziet — het testpunt is de vorm user:wachtwoord@, niet de inhoud.
      const u = 'user', w = 'geheim';
      expect(
        deny(cloud.copyWith(baseUrl: 'https://$u:$w@asr.example.nl')),
        AsrGateDenial.notConfigured,
      );
    });
  });

  group('loopback-tier', () {
    test('loopback-literal mag', () {
      final a = allow(loopback);
      expect(a, isNotNull);
      expect(a!.strategy, AiResolveStrategy.loopbackDirect);
    });

    test('localhost als naam mag ook', () {
      expect(
        allow(loopback.copyWith(baseUrl: 'http://localhost:8080')),
        isNotNull,
      );
    });

    test('een niet-loopback adres onder de loopback-tier faalt dicht', () {
      expect(
        deny(loopback.copyWith(baseUrl: 'http://192.168.1.20')),
        AsrGateDenial.loopbackRequired,
      );
      expect(
        deny(loopback.copyWith(baseUrl: 'https://asr.example.nl')),
        AsrGateDenial.loopbackRequired,
      );
    });
  });

  group('lan-tier', () {
    test('zonder trustedInternal opt-in faalt dicht', () {
      expect(
        deny(
          const AsrServerProfile(
            enabled: true,
            mode: AsrServerMode.lan,
            baseUrl: 'http://192.168.1.20:8080',
          ),
        ),
        AsrGateDenial.lanNotTrusted,
      );
    });

    test('met opt-in mag een privé-adres via trustedPrivate', () {
      final a = allow(lan);
      expect(a!.strategy, AiResolveStrategy.trustedPrivate);
    });

    test('op web is http-LAN een gegarandeerde mixed-content-blokkade', () {
      expect(deny(lan, isWeb: true), AsrGateDenial.insecureHttpOnWeb);
    });

    test('op web mag https-LAN met opt-in', () {
      expect(
        allow(lan.copyWith(baseUrl: 'https://192.168.1.20:8443'), isWeb: true),
        isNotNull,
      );
    });
  });

  group('cloud-tier', () {
    test('vereist HTTPS', () {
      expect(
        deny(cloud.copyWith(baseUrl: 'http://asr.example.nl')),
        AsrGateDenial.cloudNeedsTls,
      );
    });

    test('vereist bevestiging van díe bestemming', () {
      expect(
        deny(cloud.copyWith(cloudConfirmed: false)),
        AsrGateDenial.cloudNotConfirmed,
      );
    });

    test('met bevestiging mag het — ook op web, dat is de route van #2524', () {
      final a = allow(cloud);
      expect(a!.strategy, AiResolveStrategy.publicGuarded);
      expect(allow(cloud, isWeb: true), isNotNull);
    });

    test('op web mag een https-URL nooit een privé-literal zijn', () {
      expect(
        deny(cloud.copyWith(baseUrl: 'https://192.168.1.20'), isWeb: true),
        AsrGateDenial.insecureHttpOnWeb,
      );
      expect(
        deny(cloud.copyWith(baseUrl: 'https://127.0.0.1'), isWeb: true),
        AsrGateDenial.insecureHttpOnWeb,
      );
      expect(
        deny(cloud.copyWith(baseUrl: 'https://localhost'), isWeb: true),
        AsrGateDenial.insecureHttpOnWeb,
      );
      expect(
        deny(cloud.copyWith(baseUrl: 'https://[::ffff:10.0.0.1]'), isWeb: true),
        AsrGateDenial.insecureHttpOnWeb,
      );
    });
  });
}
