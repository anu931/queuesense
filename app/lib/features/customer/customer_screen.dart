import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/live_queue.dart';
import '../../core/store.dart';
import '../../widgets/common.dart';
import 'ticket_session.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({
    super.key,
    required this.serviceId,
    this.joinIfNeeded = true,
  });
  final int serviceId;
  final bool joinIfNeeded;
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

typedef _St = ({String key, int pos, int eta});

class _CustomerScreenState extends State<CustomerScreen> {
  Map<String, dynamic>? ticket;
  LiveQueue? live;
  String? error;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    try {
      final t = await TicketSession.open(
        widget.serviceId,
        join: widget.joinIfNeeded,
      );
      if (!mounted) return;
      if (t == null) {
        Navigator.of(context).pop();
        return;
      }
      ticket = t;
      live = LiveQueue(widget.serviceId)..addListener(_onLive);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(
        () => error = e is ApiError && e.status == 404
            ? 'This queue no longer exists.'
            : (e is ApiError ? e.message : '$e'),
      );
    }
  }

  @override
  void dispose() {
    live?.removeListener(_onLive);
    live?.dispose();
    super.dispose();
  }

  _St _status() {
    final q = live!;
    if (q.state == LinkState.closed) return (key: 'closed', pos: 0, eta: 0);
    if (q.data == null) return (key: 'loading', pos: 0, eta: 0);
    final id = ticket!['id'];
    if (q.servingId == id) return (key: 'turn', pos: 0, eta: 0);
    for (final w in q.waiting) {
      if (w['id'] == id) {
        final pos = w['position'] as int;
        return (
          key: pos <= 2 ? 'near' : 'waiting',
          pos: pos,
          eta: w['eta_seconds'] as int,
        );
      }
    }
    return (key: 'over', pos: 0, eta: 0);
  }

  /// Vibrate when the state changes; forget the ticket once it is finished.
  void _onLive() {
    final s = _status().key;
    if (s == _last) return;
    _last = s;
    if (s == 'turn') HapticFeedback.heavyImpact();
    if (s == 'near') HapticFeedback.mediumImpact();
    if (s == 'over' || s == 'closed') Store.clearTicket();
  }

  Future<void> _leave() async {
    final ok = await confirm(
      context,
      'Leave the queue?',
      'You will lose your place at #${ticket!['number']}.',
      yes: 'Leave',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await Api.cancel(ticket!['id'] as int, ticket!['key'] as String);
      await Store.clearTicket();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Notice(
          icon: Icons.error_outline,
          title: 'Couldn’t join',
          message: error!,
          actionLabel: 'Try again',
          onAction: _start,
        ),
      );
    }
    final q = live;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: q,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('${ticket!['service_name'] ?? 'Your ticket'}'),
          actions: [LinkPill(q.state), const SizedBox(width: 12)],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _content(_status(), q, cs),
          ),
        ),
      ),
    );
  }

  Widget _content(_St st, LiveQueue q, ColorScheme cs) {
    switch (st.key) {
      case 'loading':
        return const Center(child: CircularProgressIndicator());
      case 'closed':
        return Notice(
          icon: Icons.block,
          title: 'This queue was closed',
          message: 'Staff removed this service. Please pick another one.',
          actionLabel: 'Back to home',
          onAction: () => Navigator.of(context).pop(),
        );
      case 'over':
        return Notice(
          icon: Icons.check_circle_outline,
          title: 'You’re all done',
          message: 'Your ticket is closed. Thanks for waiting!',
          actionLabel: 'Back to home',
          onAction: () => Navigator.of(context).pop(),
        );
    }

    final turn = st.key == 'turn';
    final near = st.key == 'near';
    final c1 = turn ? Colors.green.shade600 : cs.primary;
    final c2 = turn ? Colors.teal.shade600 : cs.tertiary;
    final headline = turn
        ? 'It’s your turn — head to the counter'
        : near
        ? (st.pos == 1
              ? 'You’re next — staff will call you shortly'
              : 'Almost your turn — get ready')
        : 'You’re in the queue';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [c1, c2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              const Text(
                'YOUR TICKET',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '#${ticket!['number']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 80,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!turn)
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.groups_2_outlined,
                  label: 'Ahead of you',
                  value: '${st.pos - 1}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.timer_outlined,
                  label: 'Est. wait',
                  value: st.pos == 1 && q.nowServing == null
                      ? 'Next'
                      : etaText(st.eta),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.campaign_outlined,
                  label: 'Now serving',
                  value: q.nowServing == null ? '—' : '#${q.nowServing}',
                ),
              ),
            ],
          ),
        if (!turn) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            label: const Text('Leave queue'),
          ),
        ],
      ],
    );
  }
}
