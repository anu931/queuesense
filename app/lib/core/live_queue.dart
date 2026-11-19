import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

enum LinkState { connecting, live, offline, closed }

/// Live snapshot of one service's queue. Reconnects with backoff, pings every 25 s.
class LiveQueue extends ChangeNotifier {
  LiveQueue(this.serviceId) {
    _connect();
  }

  final int serviceId;
  Map<String, dynamic>? data;
  LinkState state = LinkState.connecting;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping, _retry;
  int _attempt = 0;
  bool _disposed = false;

  int? get nowServing => data?['now_serving'] as int?;
  int? get servingId => data?['serving_id'] as int?;
  List<Map<String, dynamic>> get waiting => ((data?['waiting'] ?? []) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  void _set(LinkState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  void _connect() {
    if (_disposed) return;
    if (data == null) _set(LinkState.connecting);
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse(ServerConfig.wsUrl(serviceId)),
      );
      _ch = ch;
      ch.ready.catchError((_) {});
      _sub = ch.stream.listen(
        _onMessage,
        onError: (_) => _lost(),
        onDone: _lost,
      );
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          ch.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _lost();
    }
  }

  void _onMessage(dynamic raw) {
    final j = jsonDecode(raw as String) as Map<String, dynamic>;
    if (j['type'] == 'service_deleted') {
      _teardown();
      _set(LinkState.closed);
      return;
    }
    data = j;
    _attempt = 0;
    _set(LinkState.live);
  }

  void _lost() {
    if (_disposed || state == LinkState.closed) return;
    final deleted = _ch?.closeCode == 4404;
    _teardown();
    if (deleted) {
      _set(LinkState.closed);
      return;
    }
    _set(LinkState.offline);
    final secs = min(15, 1 << min(_attempt, 4));
    _attempt++;
    _retry = Timer(Duration(seconds: secs), _connect);
  }

  void _teardown() {
    _ping?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }

  void retryNow() {
    _teardown();
    _attempt = 0;
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    super.dispose();
  }
}
