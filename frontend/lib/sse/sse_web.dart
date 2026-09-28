import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data' show Uint8List;

import 'package:web/web.dart' as web;

/// Server-Sent-Events client built on the fetch API.
///
/// EventSource cannot send an `Authorization` header, so - like the original
/// React client - we read the response body stream manually.
class SseClient {
  web.ReadableStreamDefaultReader? _reader;

  /// Connects to [url] and yields `data:` payloads of each SSE event.
  /// The stream closes on `[DONE]` or when the server closes the connection.
  Stream<String> connect(String url, Map<String, String> headers) {
    final controller = StreamController<String>();

    Future<void> run() async {
      try {
        final init = JSObject();
        init.setProperty('method'.toJS, 'GET'.toJS);
        final jsHeaders = JSObject();
        headers.forEach((k, v) => jsHeaders.setProperty(k.toJS, v.toJS));
        init.setProperty('headers'.toJS, jsHeaders);

        final response =
            await web.window.fetch(url.toJS, init as web.RequestInit).toDart;

        if (response.status != 200) {
          controller.addError(
            Exception('Log stream failed (HTTP ${response.status})'),
          );
          await controller.close();
          return;
        }

        final body = response.body;
        if (body == null) {
          await controller.close();
          return;
        }
        // `getReader()` without options always returns a default reader.
        final reader =
            body.getReader() as web.ReadableStreamDefaultReader;
        _reader = reader;

        final bytes = StreamController<Uint8List>();
        final pumping = pump(reader, bytes);

        var pending = '';
        await for (final chunk in utf8.decoder.bind(bytes.stream)) {
          pending += chunk;
          var separator = pending.indexOf('\n\n');
          while (separator >= 0) {
            final event = pending.substring(0, separator);
            pending = pending.substring(separator + 2);
            final payload = extractData(event);
            if (payload != null) {
              if (payload == '[DONE]') {
                await close();
                await controller.close();
                return;
              }
              controller.add(payload);
            }
            separator = pending.indexOf('\n\n');
          }
        }
        await pumping;
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }

    unawaited(run());
    return controller.stream;
  }

  static Future<void> pump(
    web.ReadableStreamDefaultReader reader,
    StreamController<Uint8List> out,
  ) async {
    try {
      while (true) {
        final result = await reader.read().toDart;
        if (result.done) break;
        final value = result.value;
        if (value != null && value.isA<JSUint8Array>()) {
          out.add((value as JSUint8Array).toDart);
        }
      }
      await out.close();
    } catch (_) {
      await out.close();
    }
  }

  /// Cancels the underlying fetch stream (server then kills `docker logs`).
  Future<void> close() async {
    final reader = _reader;
    _reader = null;
    if (reader == null) return;
    try {
      await reader.cancel().toDart;
    } catch (_) {
      // already closed
    }
  }

  /// Returns the concatenated `data:` fields of one SSE event block.
  static String? extractData(String event) {
    final data = <String>[];
    for (final line in event.split('\n')) {
      if (line.startsWith('data:')) {
        var value = line.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        data.add(value);
      }
    }
    if (data.isEmpty) return null;
    return data.join('\n');
  }
}
