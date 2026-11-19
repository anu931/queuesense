import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/store.dart';
import '../../widgets/common.dart';
import 'staff_service_screen.dart';

class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});
  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  List<Map<String, dynamic>> services = [];
  bool loading = true;
  String? error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Api.services();
      if (!mounted) return;
      setState(() {
        services = s;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e is ApiError ? e.message : '$e';
        loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await Store.clearLogin();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _add() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New service'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Service name',
            hintText: 'e.g. Billing',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await Api.createService(name.trim());
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final id = s['id'] as int;
    final ok = await confirm(
      context,
      'Delete “${s['name']}”?',
      'The service and its ticket history will be removed. This cannot be undone.',
      yes: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      try {
        await Api.deleteService(id);
      } on ApiError catch (e) {
        if (e.status != 409) rethrow;
        if (!mounted) return;
        final force = await confirm(
          context,
          'Customers are still waiting',
          '${e.message}\n\nDelete anyway? Their tickets will be closed.',
          yes: 'Delete anyway',
          danger: true,
        );
        if (!force) return;
        await Api.deleteService(id, force: true);
      }
      if (mounted) toast(context, '“${s['name']}” deleted');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final waiting = services.fold<int>(0, (a, s) => a + (s['waiting'] as int));
    final active = services.where((s) => s['now_serving'] != null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                Store.username ?? '',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New service'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && services.isEmpty
          ? Notice(
              icon: Icons.cloud_off,
              title: 'Can’t reach the server',
              message: error!,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              icon: Icons.layers_outlined,
                              label: 'Services',
                              value: '${services.length}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatTile(
                              icon: Icons.groups_2_outlined,
                              label: 'Waiting',
                              value: '$waiting',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatTile(
                              icon: Icons.record_voice_over_outlined,
                              label: 'Being served',
                              value: '$active',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (services.isEmpty)
                        const Notice(
                          icon: Icons.add_business_outlined,
                          title: 'No services yet',
                          message:
                              'Tap “New service” to create your first queue.',
                        ),
                      for (final s in services) _card(s, cs),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> s, ColorScheme cs) {
    final serving = s['now_serving'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: .5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StaffServiceScreen(service: s)),
          );
          if (mounted) _load();
        },
        title: Text(
          '${s['name']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${s['waiting']} waiting · now serving ${serving == null ? '—' : '#$serving'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') _delete(s);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete service'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
