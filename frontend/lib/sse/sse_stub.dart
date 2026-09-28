/// Non-web stub: the real implementation lives in sse_web.dart and is
/// selected via conditional export in ../sse_client.dart.
class SseClient {
  Stream<String> connect(String url, Map<String, String> headers) {
    return Stream.error(UnsupportedError('SSE is only available on the web'));
  }

  Future<void> close() async {}

  static String? extractData(String event) => null;
}
