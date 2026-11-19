import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Everything that must survive a refresh or app restart.
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    ServerConfig.saved = _p.getString('host') ?? '';
  }

  // staff login
  static String? get token => _p.getString('token');
  static String? get username => _p.getString('username');
  static Future<void> saveLogin(String token, String user) async {
    await _p.setString('token', token);
    await _p.setString('username', user);
  }

  static Future<void> clearLogin() async {
    await _p.remove('token');
    await _p.remove('username');
  }

  // the customer's active ticket
  static Map<String, dynamic>? get ticket {
    final s = _p.getString('ticket');
    if (s == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTicket(Map<String, dynamic> t) =>
      _p.setString('ticket', jsonEncode(t));
  static Future<void> clearTicket() => _p.remove('ticket');

  // server address (needed on Android)
  static Future<void> saveHost(String h) async {
    h = h
        .trim()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');

    if (h.isNotEmpty && !h.contains(':')) h = '$h:8000';

    ServerConfig.saved = h;
    if (h.isEmpty) {
      await _p.remove('host');
    } else {
      await _p.setString('host', h);
    }
  }
}
