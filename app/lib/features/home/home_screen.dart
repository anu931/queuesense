import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/store.dart';
import '../../widgets/common.dart';
import '../customer/customer_screen.dart';
import '../staff/login_screen.dart';
import '../staff/staff_home_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> services = [];
  bool loading = true;
  String? error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!ServerConfig.isSet) {
      if (mounted) setState(() => loading = false);
      return;
    }
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

  /// Only a QR link (?service=ID) opens a queue automatically.
  /// A saved ticket shows as the "Open" card on Home instead.
  void _autoOpen() {
    final link = int.tryParse(Uri.base.queryParameters['service'] ?? '');
    if (link != null) _openCustomer(link);
  }

  Future<void> _openCustomer(int id, {bool join = true}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerScreen(serviceId: id, joinIfNeeded: join),
      ),
    );
    if (mounted) {
      setState(() {});
      _load();
    }
  }

  Future<void> _staff() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            Store.token != null ? const StaffHomeScreen() : const LoginScreen(),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _server() async {
    if (await editServerAddress(context) && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final waiting = services.fold<int>(0, (a, s) => a + (s['waiting'] as int));
    final ticket = Store.ticket;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(cs, waiting),
                  const SizedBox(height: 16),
                  if (ticket != null) _ticketCard(ticket, cs),
                  ..._body(cs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs, int waiting) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: LinearGradient(
        colors: [cs.primary, cs.tertiary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.confirmation_number_rounded, color: cs.onPrimary),
            const SizedBox(width: 8),
            Text(
              'QueueSense',
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Server address',
              onPressed: _server,
              icon: Icon(Icons.settings_ethernet, color: cs.onPrimary),
            ),
            IconButton(
              tooltip: 'Staff',
              onPressed: _staff,
              icon: Icon(Icons.badge_outlined, color: cs.onPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Skip the line,\nnot your turn.',
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          services.isEmpty
              ? 'Pick a service to join its virtual queue.'
              : '$waiting waiting across ${services.length} services right now',
          style: TextStyle(color: cs.onPrimary.withValues(alpha: .85)),
        ),
      ],
    ),
  );

  Widget _ticketCard(Map<String, dynamic> t, ColorScheme cs) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 0,
    color: cs.secondaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(Icons.confirmation_number, color: cs.onSecondaryContainer),
      title: Text(
        'Your ticket #${t['number']}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onSecondaryContainer,
        ),
      ),
      subtitle: Text(
        '${t['service_name'] ?? 'Active queue'}',
        style: TextStyle(color: cs.onSecondaryContainer),
      ),
      trailing: FilledButton(
        onPressed: () => _openCustomer(t['service_id'] as int, join: false),
        child: const Text('Open'),
      ),
    ),
  );

  List<Widget> _body(ColorScheme cs) {
    if (!ServerConfig.isSet) {
      return [
        Notice(
          icon: Icons.wifi_find,
          title: 'Connect to your server',
          message:
              'Enter the address of the QueueSense backend to get started.',
          actionLabel: 'Set server address',
          onAction: _server,
        ),
      ];
    }
    if (loading) {
      return [
        const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (error != null && services.isEmpty) {
      return [
        Notice(
          icon: Icons.cloud_off,
          title: 'Can’t reach the server',
          message: error!,
          actionLabel: 'Try again',
          onAction: _load,
        ),
      ];
    }
    if (services.isEmpty) {
      return [
        const Notice(
          icon: Icons.inbox_outlined,
          title: 'No services yet',
          message: 'Ask staff to add a service.',
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'Choose a service',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      for (final s in services) _serviceCard(s, cs),
    ];
  }

  Widget _serviceCard(Map<String, dynamic> s, ColorScheme cs) {
    final name = s['name'] as String;
    final serving = s['now_serving'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: .5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCustomer(s['id'] as int),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Now serving ${serving == null ? '—' : '#$serving'} · ~${s['minutes_per_person']} min each',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${s['waiting']}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  Text('waiting', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
