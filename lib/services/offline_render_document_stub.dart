/// Browser builds render directly and never start a native document host.
class OfflineRenderDocument {
  Uri get uri => throw UnsupportedError('native renderer only');
  static Future<OfflineRenderDocument> start(String html) =>
      throw UnsupportedError('native renderer only');
  Future<void> close() async {}
}
