import 'package:flutter/material.dart';
import '../../../core/ui/mesh_widgets.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/ui/server_config_dialog.dart';
import '../../auth/screens/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AuthService authService;
  const SettingsScreen({super.key, required this.authService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Make yourself at home.',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('A calmer space, in your preferred light.'),
          const SizedBox(height: 28),
          GlassSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Appearance',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppearanceController.instance,
                    builder: (context, mode, _) => Column(
                        children: ThemeMode.values
                            .map((option) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(option == ThemeMode.system
                                      ? Icons.brightness_auto_outlined
                                      : option == ThemeMode.light
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined),
                                  title: Text(option == ThemeMode.system
                                      ? 'Follow system'
                                      : option == ThemeMode.light
                                          ? 'Light'
                                          : 'Dark'),
                                  trailing: Icon(
                                      mode == option
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  selected: mode == option,
                                  onTap: () async {
                                    try {
                                      await AppearanceController.instance
                                          .select(option);
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Couldn’t save appearance. Try again.')));
                                      }
                                    }
                                  },
                                ))
                            .toList())),
                Text('Motion follows your device’s accessibility settings.',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          const SizedBox(height: 20),
          GlassSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: const Text('Server (Local Wi-Fi)'),
                  subtitle: Text(AppConfig.backendBaseUrl),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ServerConfigDialog.show(
                      context,
                      onSaved: () {
                        widget.authService.updateBaseUrl(AppConfig.backendBaseUrl);
                        setState(() {});
                      },
                    );
                  })),
          const SizedBox(height: 20),
          GlassSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                  leading: const Icon(Icons.cell_tower_rounded),
                  title: const Text('STUN / TURN Calling Servers'),
                  subtitle: const Text('WebRTC NAT traversal configuration'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showIceServersDialog(context))),
          const SizedBox(height: 20),
          GlassSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Log out'),
                  subtitle: const Text('Sign out of this account'),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: const Text('Log out?'),
                                content: const Text(
                                    'You can sign back in with your account credentials.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Log out'))
                                ]));
                    if (confirmed != true) {
                      return;
                    }
                    await widget.authService.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) =>
                                  LoginScreen(authService: widget.authService)),
                          (route) => false);
                    }
                  })),
          const SizedBox(height: 28),
          const Center(
              child: Text('OFFLINEMESH',
                  style: TextStyle(
                      letterSpacing: 3,
                      fontSize: 11,
                      fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Center(
              child: Text('Communication, beyond a single connection.',
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );

  Future<void> _showIceServersDialog(BuildContext context) async {
    final currentServers = await AppConfig.getIceServers();
    if (!context.mounted) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDefault = currentServers == AppConfig.defaultIceServers;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.cell_tower_rounded, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('ICE Calling Servers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STUN and TURN servers help negotiate WebRTC audio and video calls across different networks and NAT firewalls.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Text('Active ICE Server URLs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...currentServers.map((server) {
                    final urls = server['urls'];
                    final urlList = urls is List ? urls : [urls.toString()];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: urlList.map((u) => Text(
                          u.toString(),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        )).toList(),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Add STUN/TURN URL',
                      hintText: 'e.g. turn:myturn.example.com:3478',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isDefault)
                TextButton(
                  onPressed: () async {
                    await AppConfig.setCustomIceServers(AppConfig.defaultIceServers);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Reset to Default', style: TextStyle(color: Colors.redAccent)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isNotEmpty) {
                    final updated = List<Map<String, dynamic>>.from(currentServers)
                      ..add({'urls': [text]});
                    await AppConfig.setCustomIceServers(updated);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
