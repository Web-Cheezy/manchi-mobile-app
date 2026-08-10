import 'package:flutter/material.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/features/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<SavedNotification> _notifications = [];
  bool _loading = true;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _load();
    _notificationService.onNotificationsUpdated = _load;
  }

  @override
  void dispose() {
    _notificationService.onNotificationsUpdated = null;
    super.dispose();
  }

  /// Load from backend first; fall back to local storage if backend fails or returns nothing.
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final backendList = await BackendService.getNotifications();
      if (backendList.isNotEmpty) {
        final list = backendList
            .map((e) => SavedNotification.fromBackendJson(e))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!mounted) return;
        setState(() {
          _notifications = list;
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // Backend not implemented or error – use local
    }

    final localList = await _notificationService.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = localList;
      _loading = false;
    });
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inDays > 7) {
      return DateFormat('MMM d, y').format(dateTime);
    }
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    return 'Just now';
  }

  Future<void> _markAsRead(SavedNotification n) async {
    if (n.isRead) return;
    final ok = await BackendService.markNotificationRead(n.id);
    if (!ok) {
      await _notificationService.markAsRead(n.id);
    }
    _load();
  }

  Future<void> _clearAll() async {
    await BackendService.clearNotifications();
    await _notificationService.clearAll();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear all'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.bellOff,
                        size: 64,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Order updates and promos will show here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      return Container(
                        key: ValueKey(n.id),
                        decoration: BoxDecoration(
                          color: n.isRead
                              ? Colors.transparent
                              : theme.colorScheme.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: n.isRead
                                ? theme.colorScheme.surfaceContainerHighest
                                : theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(
                              LucideIcons.bell,
                              color: n.isRead
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                n.body,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _timeAgo(n.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _markAsRead(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
