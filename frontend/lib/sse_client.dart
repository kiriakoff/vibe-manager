// Conditional export: the fetch-based SSE client on the web,
// a stub everywhere else (keeps `flutter test` on the VM compiling).
export 'sse/sse_stub.dart' if (dart.library.js_interop) 'sse/sse_web.dart';
