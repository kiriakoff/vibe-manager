import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'sse_client.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? apiBase, this.token})
      : baseUrl = apiBase ?? defaultBaseUrl;

  /// Empty string = same origin (production). Override for local dev:
  /// `flutter run --dart-define=API_BASE=http://localhost:8000`
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: '',
  );

  final String baseUrl;
  String? token;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response response) {
    final body = response.body;
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  dynamic _check(http.Response response) {
    final data = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    final detail =
        data is Map<String, dynamic> ? data['detail']?.toString() : null;
    throw ApiException(
      detail ?? 'Request failed (HTTP ${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  /// POST /auth/login
  Future<LoginResult> login(String username, String password) async {
    final response = await http.post(
      _uri('/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return LoginResult.fromJson(
      Map<String, dynamic>.from(_check(response) as Map),
    );
  }

  /// GET /api/apps
  Future<List<AppInfo>> listApps() async {
    final response = await http.get(_uri('/api/apps'), headers: _headers);
    final data = _check(response);
    if (data is! Map<String, dynamic>) return const [];
    final apps = data['apps'];
    if (apps is! List) return const [];
    return apps
        .whereType<Map>()
        .map((e) => AppInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// POST /api/apps/{fqdn}/start
  Future<String> startApp(String fqdn) async {
    final response = await http.post(
      _uri('/api/apps/$fqdn/start'),
      headers: _headers,
    );
    final data = _check(response);
    return data is Map<String, dynamic>
        ? data['message']?.toString() ?? 'Started'
        : 'Started';
  }

  /// POST /api/apps/{fqdn}/stop
  Future<String> stopApp(String fqdn) async {
    final response = await http.post(
      _uri('/api/apps/$fqdn/stop'),
      headers: _headers,
    );
    final data = _check(response);
    return data is Map<String, dynamic>
        ? data['message']?.toString() ?? 'Stopped'
        : 'Stopped';
  }

  /// GET /api/apps/{fqdn}/status
  Future<String> appStatus(String fqdn) async {
    final response =
        await http.get(_uri('/api/apps/$fqdn/status'), headers: _headers);
    final data = _check(response);
    return data is Map<String, dynamic>
        ? data['status']?.toString() ?? 'not found'
        : 'not found';
  }

  /// POST /api/previews/{fqdn}/refresh
  Future<String> refreshPreview(String fqdn) async {
    final response = await http.post(
      _uri('/api/previews/$fqdn/refresh'),
      headers: _headers,
    );
    final data = _check(response);
    return data is Map<String, dynamic>
        ? data['message']?.toString() ?? 'Preview refreshed'
        : 'Preview refreshed';
  }

  /// GET /api/apps/{fqdn}/logs - live SSE stream of container logs.
  Stream<String> streamLogs(String fqdn) {
    final client = SseClient();
    return client.connect(
      '$baseUrl/api/apps/$fqdn/logs',
      {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'text/event-stream',
      },
    );
  }

  /// Public preview image URL (no auth needed, like the original).
  Uri previewUrl(String fqdn, {int? cacheBuster}) {
    final query = cacheBuster != null ? {'t': '$cacheBuster'} : null;
    return Uri.parse('$baseUrl/api/previews/$fqdn').replace(queryParameters: query);
  }
}
