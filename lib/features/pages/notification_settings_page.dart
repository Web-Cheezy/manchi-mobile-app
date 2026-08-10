import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _storage = const FlutterSecureStorage();

  bool _pushNotifications = false;
  bool _appUpdates = false;
  bool _discounts = false;
  bool _receipts = false;
  bool _newsletters = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final push =
        await _storage.read(key: 'notifications_push') == 'true';
    final updates =
        await _storage.read(key: 'notifications_updates') == 'true';
    final discounts =
        await _storage.read(key: 'notifications_discounts') == 'true';
    final receipts =
        await _storage.read(key: 'notifications_receipts') == 'true';
    final newsletters =
        await _storage.read(key: 'notifications_newsletters') == 'true';

    if (!mounted) return;
    setState(() {
      _pushNotifications = push;
      _appUpdates = updates;
      _discounts = discounts;
      _receipts = receipts;
      _newsletters = newsletters;
      _loading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isRestricted) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Control how you receive notifications from the app.',
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Notification permissions'),
                  subtitle: const Text(
                    'Allow the app to send push notifications.',
                  ),
                  trailing: TextButton(
                    onPressed: _requestNotificationPermission,
                    child: const Text('Allow'),
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Push notifications'),
                  subtitle: const Text('Order updates and important alerts'),
                  value: _pushNotifications,
                  onChanged: (value) async {
                    setState(() => _pushNotifications = value);
                    await _saveSetting('notifications_push', value);
                    if (value) {
                      await _requestNotificationPermission();
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('App updates'),
                  subtitle: const Text('New features and improvements'),
                  value: _appUpdates,
                  onChanged: (value) async {
                    setState(() => _appUpdates = value);
                    await _saveSetting('notifications_updates', value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Discounts and promotions'),
                  subtitle: const Text('Special offers and promo codes'),
                  value: _discounts,
                  onChanged: (value) async {
                    setState(() => _discounts = value);
                    await _saveSetting('notifications_discounts', value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Receipts'),
                  subtitle: const Text('Receive digital receipts'),
                  value: _receipts,
                  onChanged: (value) async {
                    setState(() => _receipts = value);
                    await _saveSetting('notifications_receipts', value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Newsletters'),
                  subtitle: const Text('Food tips and news from the app'),
                  value: _newsletters,
                  onChanged: (value) async {
                    setState(() => _newsletters = value);
                    await _saveSetting('notifications_newsletters', value);
                  },
                ),
              ],
            ),
    );
  }
}

