import 'package:flutter/foundation.dart';

/// Where the backend lives. Web debug: same machine, port 8000.
/// Web release: same origin (backend serves the build). Android: set in the app or via API_HOST.
class ServerConfig {
  static String saved = '';
  static const String _define = String.fromEnvironment('API_HOST');

  static String _clean(String v) {
    var s = v
        .trim()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    if (s.isNotEmpty && !s.contains(':')) s = '$s:8000';
    return s;
  }

  static String get host {
    if (saved.isNotEmpty) return _clean(saved);
    if (_define.isNotEmpty) return _clean(_define);
    if (kIsWeb) {
      return kReleaseMode ? Uri.base.authority : '${Uri.base.host}:8000';
    }
    return '';
  }

  static bool get isSet => host.isNotEmpty;

  static bool get _secure =>
      kIsWeb && kReleaseMode && _define.isEmpty && Uri.base.scheme == 'https';

  static String get httpBase => '${_secure ? 'https' : 'http'}://$host';
  static String wsUrl(int serviceId) =>
      '${_secure ? 'wss' : 'ws'}://$host/ws/$serviceId';

  /// Link encoded in the QR code. Opens the customer page for this service.
  static String joinLink(int serviceId) => kIsWeb
      ? '${Uri.base.origin}/?service=$serviceId'
      : 'http://$host/?service=$serviceId';
}
