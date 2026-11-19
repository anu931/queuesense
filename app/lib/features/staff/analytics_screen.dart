import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../widgets/common.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.serviceId,
    required this.name,
  });
  final int serviceId;
  final String name;
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? d;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final r = await Api.analytics(widget.serviceId);
      if (mounted) setState(() => d = r);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiError && e.status == 401) {
        showError(context, e);
        return;
      }
      setState(() => error = e is ApiError ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.name} · Analytics')),
      body: error != null
          ? Notice(
              icon: Icons.error_outline,
              title: 'Couldn’t load analytics',
              message: error!,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, d!),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> d) {
    final cs = Theme.of(context).colorScheme;
    if ((d['samples'] as int) == 0) {
      return const Notice(
        icon: Icons.insights_outlined,
        title: 'Not enough history yet',
        message: 'Serve a few customers and the charts will appear here.',
      );
    }
    final wait = (d['wait_by_hour'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    final peak = d['peak_hour'] as int?;
    final trend = (d['trend'] as List).cast<Map<String, dynamic>>();
    final tMax = trend.fold<double>(
      0,
      (a, t) => (t['avg_service_min'] as num).toDouble() > a
          ? (t['avg_service_min'] as num).toDouble()
          : a,
    );
    final wMax = wait.fold<double>(0, (a, v) => v > a ? v : a);

    Widget card(String title, Widget child) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.hourglass_bottom,
                    label: 'Avg wait',
                    value: '${d['avg_wait_min']} min',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    icon: Icons.support_agent,
                    label: 'Avg service',
                    value: '${d['avg_service_min']} min',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    icon: Icons.schedule,
                    label: 'Longest waits',
                    value: peak == null ? '—' : hourLabel(peak),
                  ),
                ),
              ],
            ),
            card(
              'Average wait by hour (min)',
              Column(
                children: [
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var h = 0; h < 24; h++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              child: Container(
                                height: wMax == 0
                                    ? 2
                                    : 2 + 116 * (wait[h] / wMax),
                                decoration: BoxDecoration(
                                  color: h == peak ? cs.tertiary : cs.primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final h in [0, 6, 12, 18, 23])
                        Text(
                          hourLabel(h),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            card(
              'Service time, last days (min)',
              Column(
                children: [
                  for (final t in trend)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(width: 56, child: Text('${t['day']}')),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                minHeight: 10,
                                value: tMax == 0
                                    ? 0
                                    : (t['avg_service_min'] as num).toDouble() /
                                          tMax,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${t['avg_service_min']}',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Based on ${d['samples']} served customers (last 14 days).',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
