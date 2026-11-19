import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/live_queue.dart';
import '../core/store.dart';

String etaText(num seconds) =>
    seconds < 60 ? '< 1 min' : '${(seconds / 60).ceil()} min';

String hourLabel(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 ${h < 12 ? 'AM' : 'PM'}';
}

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
}

/// Call only when the widget is still mounted.
void showError(BuildContext c, Object e) {
  if (e is ApiError && e.status == 401) {
    toast(c, 'Session expired. Please sign in again.');
    Navigator.of(c).popUntil((r) => r.isFirst);
    return;
  }
  toast(c, e is ApiError ? e.message : 'Something went wrong');
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String yes = 'Confirm',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Returns true if the address was saved.
Future<bool> editServerAddress(BuildContext context) async {
  final c = TextEditingController(text: ServerConfig.saved);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('IP and port of the QueueSense backend.'),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '192.168.1.5:8000',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await Store.saveHost(c.text);
  return true;
}

class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class LinkPill extends StatelessWidget {
  const LinkPill(this.state, {super.key});
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      LinkState.live => ('Live', Colors.green),
      LinkState.connecting => ('Connecting', Colors.orange),
      LinkState.offline => ('Reconnecting', Colors.red),
      LinkState.closed => ('Closed', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
