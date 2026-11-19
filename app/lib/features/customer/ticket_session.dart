import '../../core/api.dart';
import '../../core/store.dart';

class TicketSession {
  /// Resume the saved ticket if it is still valid. Otherwise join (when [join]) or return null.
  static Future<Map<String, dynamic>?> open(
    int serviceId, {
    required bool join,
  }) async {
    final saved = Store.ticket;
    if (saved != null && saved['service_id'] == serviceId) {
      try {
        final t = await Api.ticket(saved['id'] as int);
        if (t['status'] == 'waiting' || t['status'] == 'serving') return saved;
        await Store.clearTicket();
      } on ApiError catch (e) {
        if (e.status == 0) {
          return saved; // offline: keep the ticket, the socket will reconnect
        }
        await Store.clearTicket();
      }
    }
    if (!join) return null;

    final t = await Api.join(serviceId);
    var name = 'Queue';
    try {
      final all = await Api.services();
      name =
          all.firstWhere(
                (s) => s['id'] == serviceId,
                orElse: () => <String, dynamic>{'name': 'Queue'},
              )['name']
              as String;
    } catch (_) {}
    final ticket = {...t, 'service_name': name};
    await Store.saveTicket(ticket);
    return ticket;
  }
}
