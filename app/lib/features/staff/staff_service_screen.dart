import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/live_queue.dart';
import '../../widgets/common.dart';
import 'analytics_screen.dart';

class StaffServiceScreen extends StatefulWidget {
  const StaffServiceScreen({super.key, required this.service});
  final Map<String, dynamic> service;
  @override
  State<StaffServiceScreen> createState() => _StaffServiceScreenState();
}

class _StaffServiceScreenState extends State<StaffServiceScreen> {
  late final LiveQueue live;
  bool _busy = false, _left = false;

  int get _id => widget.service['id'] as int;
  String get _name => widget.service['name'] as String;

  @override
  void initState() {
    super.initState();
    live = LiveQueue(_id)..addListener(_watchClosed);
  }

  @override
  void dispose() {
    live.removeListener(_watchClosed);
    live.dispose();
    super.dispose();
  }

  void _watchClosed() {
    if (live.state == LinkState.closed && !_left && mounted) {
      _left = true;
      toast(context, 'This service was deleted');
      Navigator.of(context).pop();
    }
  }

  Future<void> _do(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _qr() {
    final link = ServerConfig.joinLink(_id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Join “$_name”'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: link,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(link, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text(
              'Customers scan this to join from their phone.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final waiting = live.waiting;
        final serving = live.servingId;
        return Scaffold(
          appBar: AppBar(
            title: Text(_name),
            actions: [
              LinkPill(live.state),
              IconButton(
                tooltip: 'QR code',
                onPressed: _qr,
                icon: const Icon(Icons.qr_code_2),
              ),
              IconButton(
                tooltip: 'Analytics',
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AnalyticsScreen(serviceId: _id, name: _name),
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'NOW SERVING',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            letterSpacing: 2,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          live.nowServing == null ? '—' : '#${live.nowServing}',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontSize: 72,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  _busy || (waiting.isEmpty && serving == null)
                                  ? null
                                  : () => _do(() => Api.callNext(_id)),
                              icon: const Icon(Icons.skip_next),
                              label: const Text('Call next'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy || serving == null
                                  ? null
                                  : () => _do(() => Api.complete(serving)),
                              icon: const Icon(Icons.check),
                              label: const Text('Complete'),
                            ),
                            TextButton.icon(
                              onPressed: _busy || serving == null
                                  ? null
                                  : () => _do(() => Api.skip(serving)),
                              icon: const Icon(Icons.person_off_outlined),
                              label: const Text('No-show'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Waiting (${waiting.length})',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (waiting.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Nobody is waiting',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  for (final w in waiting)
                    Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: cs.surfaceContainerHighest.withValues(alpha: .5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.secondaryContainer,
                          child: Text(
                            '${w['number']}',
                            style: TextStyle(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text('Ticket #${w['number']}'),
                        subtitle: Text(
                          'Position ${w['position']} · ~${etaText(w['eta_seconds'] as int)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: _busy
                              ? null
                              : () => _do(() => Api.skip(w['id'] as int)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
