// Fabriek voor de live-serverengine (§4.3, #2525): koppelt het profiel
// aan de platform-WS-transport en de platform-audiolezer — hetzelfde
// recept als `asr_engine_factory` voor de batchroute.
//
// De API-sleutel wordt per verbinding uit de sleutelbos gelezen
// ([SecretStore.readAsrApiKey], gekeyd op `baseUrl` — één profiel, één
// credential, ook als het live-endpoint een ander pad/poort heeft) — hij
// komt op io in de handshake-header terecht en nergens anders. Op web
// kan een WebSocket geen headers zetten: een sleutel-eisende
// live-server is daar onbereikbaar, en de sleutel gaat per contract
// nooit in de URL.
import '../../models/asr_server_profile.dart';
import '../secret_store.dart';
import 'asr_audio_source.dart';
import 'asr_live_server_engine.dart';
import 'asr_live_transport.dart';

AsrLiveServerEngine createAsrLiveServerEngine(
  AsrServerProfile profile, {
  AsrLiveTransport? transport,
  Future<String?> Function()? apiKeyReader,
}) {
  final secrets = SecretStore();
  return AsrLiveServerEngine(
    profile: profile,
    transport: transport ?? createAsrLiveTransport(),
    audioReader: readAsrAudio,
    apiKeyReader:
        apiKeyReader ??
        (() async =>
            secrets.canStore ? secrets.readAsrApiKey(profile.baseUrl) : null),
  );
}
