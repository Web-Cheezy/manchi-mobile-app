import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _openExternalLink(BuildContext context, String value) async {
    final uri = Uri.parse(value);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open that link right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.fileText),
            title: const Text('Terms and Conditions'),
            subtitle: const Text('Read terms at manchi.ng/terms'),
            trailing: const Icon(LucideIcons.externalLink),
            onTap: () => _openExternalLink(context, 'https://www.manchi.ng/terms'),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.shield),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Read policy at manchi.ng/privacy'),
            trailing: const Icon(LucideIcons.externalLink),
            onTap: () => _openExternalLink(context, 'https://www.manchi.ng/privacy'),
          ),
        ],
      ),
    );
  }
}
