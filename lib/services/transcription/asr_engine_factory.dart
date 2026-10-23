// Fabriek voor de serverengine (§4.3, #2524): koppelt het profiel aan de
// platform-transport en de platform-audiolezer. Beide helften zijn
// conditioneel — `createAsrTransport` en `readAsrAudio` resolven op
// io/web/stub; de engine zelf is platformvrij.
//
// De API-sleutel wordt per verzoek uit de sleutelbos gelezen
// ([SecretStore.readAsrApiKey], gekeyd op de basis-URL) zodat een
// vervangen sleutel meteen geldt en een profielwissel nooit een vreemde
// sleutel meestuurt. Op web is sleutelopslag onbeschikbaar; een server
// die auth eist, meldt dat eerlijk via `probe()`/`ServerRefused`.
import '../../models/asr_server_profile.dart';
import '../secret_store.dart';
import 'asr_audio_source.dart';
import 'asr_server_engine.dart';
import 'asr_transport.dart';

AsrServerEngine createAsrServerEngine(AsrServerProfile profile) {
  final secrets = SecretStore();
  return AsrServerEngine(
    profile: profile,
    apiKeyReader: () async =>
        secrets.canStore ? secrets.readAsrApiKey(profile.baseUrl) : null,
    transport: createAsrTransport(),
    audioReader: readAsrAudio,
  );
}
