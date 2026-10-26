// Web-helft: geen bestandssysteem — de manifest-JSON ligt daar als tweede
// `mem:`-asset in de WebAssetStore, gezet door de sessie zelf. Teruglezen
// kan daarom niet via een pad; de web-route kent zijn eigen assetvorm.
Future<void> writeCallSources(String stagingDir, String json) async {}

Map<String, Object?>? readCallSources(String sessionDir) => null;
