import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'pages/dashboard_page.dart';
import 'pages/login_page.dart';
import 'theme.dart';

const _kTokenKey = 'token';
const _kUserKey = 'user';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(VibeApp(
    initialToken: prefs.getString(_kTokenKey),
    initialUser: prefs.getString(_kUserKey),
  ));
}

class VibeApp extends StatefulWidget {
  final String? initialToken;
  final String? initialUser;

  const VibeApp({super.key, this.initialToken, this.initialUser});

  @override
  State<VibeApp> createState() => _VibeAppState();
}

class _VibeAppState extends State<VibeApp> {
  final ApiClient _api = ApiClient();
  String? _token;
  String? _user;

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    _user = widget.initialUser;
    _api.token = _token;
  }

  Future<void> _handleLogin(String token) async {
    // The backend embeds the username in the JWT; decode it client-side
    // (payload is plain base64url, no signature check needed here).
    final user = _usernameFromToken(token) ?? 'user';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    await prefs.setString(_kUserKey, user);
    setState(() {
      _token = token;
      _user = user;
      _api.token = token;
    });
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kUserKey);
    setState(() {
      _token = null;
      _user = null;
      _api.token = null;
    });
  }

  static String? _usernameFromToken(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    final normalized = base64Url.normalize(parts[1]);
    try {
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map;
      return payload['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe Manager',
      debugShowCheckedModeBanner: false,
      theme: VibeTheme.dark(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: (_token == null)
            ? LoginPage(key: const ValueKey('login'), api: _api, onLogin: _handleLogin)
            : DashboardPage(
                key: const ValueKey('dashboard'),
                api: _api,
                user: _user ?? 'user',
                onLogout: _handleLogout,
              ),
      ),
    );
  }
}
