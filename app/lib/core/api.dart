import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'store.dart';

class ApiError implements Exception {
  ApiError(this.message, this.status);
  final String message;
  final int status; // 0 = could not reach server
  @override
  String toString() => message;
}

class Api {
  static Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    if (!ServerConfig.isSet) throw ApiError('Server address is not set', 0);
    final uri = Uri.parse('${ServerConfig.httpBase}$path');
    final headers = <String, String>{};
    if (method == 'POST') headers['Content-Type'] = 'application/json';
    if (auth && Store.token != null) {
      headers['Authorization'] = 'Bearer ${Store.token}';
    }

    http.Response r;
    try {
      r = await (switch (method) {
        'GET' => http.get(uri, headers: headers),
        'DELETE' => http.delete(uri, headers: headers),
        _ => http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiError('Cannot reach ${ServerConfig.httpBase}\n$e', 0);
    }

    if (r.statusCode >= 400) {
      var msg = 'Request failed (${r.statusCode})';
      try {
        final d = jsonDecode(r.body)['detail'];
        if (d is String) msg = d;
      } catch (_) {}
      if (r.statusCode == 401 && auth) await Store.clearLogin();
      throw ApiError(msg, r.statusCode);
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> _obj(
    String m,
    String p, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async => Map<String, dynamic>.from(
    await _send(m, p, body: body, auth: auth) as Map,
  );

  // public
  static Future<List<Map<String, dynamic>>> services() async =>
      List<Map<String, dynamic>>.from(await _send('GET', '/services') as List);
  static Future<Map<String, dynamic>> join(int serviceId) =>
      _obj('POST', '/tickets', body: {'service_id': serviceId});
  static Future<Map<String, dynamic>> ticket(int id) =>
      _obj('GET', '/tickets/$id');
  static Future<void> cancel(int id, String key) =>
      _send('POST', '/tickets/$id/cancel', body: {'key': key});

  // staff
  static Future<Map<String, dynamic>> login(String user, String pass) =>
      _obj('POST', '/auth/login', body: {'username': user, 'password': pass});
  static Future<void> createService(String name) =>
      _send('POST', '/services', body: {'name': name}, auth: true);
  static Future<void> deleteService(int id, {bool force = false}) =>
      _send('DELETE', '/services/$id?force=$force', auth: true);
  static Future<void> callNext(int serviceId) =>
      _send('POST', '/services/$serviceId/call-next', auth: true);
  static Future<void> skip(int ticketId) =>
      _send('POST', '/tickets/$ticketId/skip', auth: true);
  static Future<void> complete(int ticketId) =>
      _send('POST', '/tickets/$ticketId/complete', auth: true);
  static Future<Map<String, dynamic>> analytics(int serviceId) =>
      _obj('GET', '/services/$serviceId/analytics', auth: true);
}
