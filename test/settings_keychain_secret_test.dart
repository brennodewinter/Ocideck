import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/widgets/dialogs/settings/keychain_secret.dart';
import 'package:ocideck/widgets/dialogs/settings/webdav_form.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';

/// De boekhouding rond een geheim dat in de sleutelhanger woont.
///
/// Deze twee fouten zijn de reden dat dit één gedeeld stukje code is. Ze geven
/// allebei geen foutmelding: in het ene geval ben je je wachtwoord kwijt, in het
/// andere staat het onder de verkeerde sleutel en werkt de verbinding niet meer.
/// Je merkt het pas als je de bron weer probeert te gebruiken.
void main() {
  group('KeychainSecret', () {
    test('schrijft niet wanneer er niets is gebeurd', () {
      final secret = KeychainSecret()..rememberIdentity('https://x|bram');
      secret.adopt('geheim');

      expect(secret.shouldWrite('https://x|bram'), isFalse);
    });

    test('schrijft wanneer de gebruiker het geheim wijzigt', () {
      final secret = KeychainSecret()..rememberIdentity('https://x|bram');
      secret.adopt('geheim');
      secret.field.text = 'ander geheim';

      expect(secret.shouldWrite('https://x|bram'), isTrue);
    });

    // De belangrijkste van het stel. Het venster leest het geheim asynchroon in;
    // wie Opslaan indrukt vóórdat dat antwoord binnen is, zou het met een leeg
    // veld overschrijven. Daarom kijkt shouldWrite naar verschil en niet naar
    // leegte — en is "nog niets ingeladen" dus géén reden om te schrijven.
    test('schrijft niet wanneer de lezing nog loopt', () {
      final secret = KeychainSecret()..rememberIdentity('https://x|bram');
      // adopt() is nooit aangeroepen: de sleutelhanger heeft nog niet geantwoord.

      expect(secret.field.text, isEmpty);
      expect(secret.shouldWrite('https://x|bram'), isFalse);
    });

    // De andere kant: het geheim is onveranderd, maar de sleutel waaronder het
    // staat verandert mee met de identiteit van de bron. Schrijven we dan niet,
    // dan blijft het onder de oude sleutel achter.
    test('schrijft wanneer de identiteit verschuift, ook zonder wijziging', () {
      final secret = KeychainSecret()..rememberIdentity('https://x|bram');
      secret.adopt('geheim');

      expect(secret.shouldWrite('https://x|anne'), isTrue);
      expect(secret.shouldWrite('https://y|bram'), isTrue);
    });
  });

  // De drie bronnen delen die boekhouding maar bouwen hun identiteit elk anders
  // op. Verwissel je die, dan schrijft een naamswijziging stilletjes naar de
  // verkeerde sleutel.
  group('identiteit per bron', () {
    test('Nextcloud sleutelt op URL en gebruiker', () {
      expect(
        WebdavForm.identityOf('https://cloud.x', 'bram'),
        'https://cloud.x|bram',
      );
    });

    test('git sleutelt op URL en eigenaar', () {
      expect(
        GitForm.identityOf('https://git.x', 'LibreKAT'),
        'https://git.x|LibreKAT',
      );
    });
  });

  group('WebdavForm', () {
    test('vult een ontbrekend schema aan en normaliseert de submap', () {
      final form = WebdavForm()
        ..url.text = 'cloud.voorbeeld.nl'
        ..user.text = 'bram'
        ..root.text = 'Presentaties';

      expect(form.server.baseUrl, 'https://cloud.voorbeeld.nl');
      expect(form.server.rootPath, WebdavServer.normalizeRoot('Presentaties'));
    });

    test('een lege bron is niet ingesteld', () {
      expect(WebdavForm().server.isConfigured, isFalse);
    });
  });

  group('GitForm', () {
    test('vult een ontbrekend schema aan', () {
      final form = GitForm()
        ..url.text = 'git.voorbeeld.org'
        ..owner.text = 'LibreKAT'
        ..repo.text = 'Ocideck';

      expect(form.config.baseUrl, 'https://git.voorbeeld.org');
      expect(form.config.isConfigured, isTrue);
    });
  });

  group('AiForm', () {
    // Anders dan de andere twee: zonder basis-URL is er geen sleutel om onder
    // te schrijven, dus loopback aanvullen gebeurt met http, niet https.
    test('vult een ontbrekend schema aan met http (loopback)', () {
      final form = AiForm()..baseUrl.text = 'localhost:11434';

      expect(form.settings.baseUrl, 'http://localhost:11434');
    });
  });
}
