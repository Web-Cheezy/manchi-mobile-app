import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:provider/provider.dart';
import 'package:manchi_app/themes/theme_provider.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final mode = themeProvider.themeMode;
          return RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null) themeProvider.setThemeMode(value);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Theme',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: const Text('Light'),
                  subtitle: const Text('Always use light theme'),
                  secondary: const Icon(LucideIcons.sun),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: const Text('Dark'),
                  subtitle: const Text('Always use dark theme'),
                  secondary: const Icon(LucideIcons.moonStar),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: const Text('System'),
                  subtitle: const Text('Follow device setting'),
                  secondary: const Icon(LucideIcons.monitorCog),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
