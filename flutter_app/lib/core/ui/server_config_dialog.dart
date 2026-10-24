import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'mesh_theme.dart';

class ServerConfigDialog extends StatefulWidget {
  final VoidCallback? onSaved;

  const ServerConfigDialog({super.key, this.onSaved});

  static Future<void> show(BuildContext context,
      {VoidCallback? onSaved}) async {
    await showDialog(
      context: context,
      builder: (ctx) => ServerConfigDialog(onSaved: onSaved),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late final TextEditingController _controller;
  bool _isTesting = false;
  bool? _testSuccess;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: AppConfig.backendBaseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testMessage = null;
    });

    try {
      final success = await AppConfig.testConnection(_controller.text);
      if (!mounted) return;
      setState(() {
        _testSuccess = success;
        _testMessage = success
            ? 'OfflineMesh backend is reachable.'
            : 'Cannot reach this server. Use the PC address on the network your phone is connected to. Check Docker, port 8081, and firewall access.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _testMessage =
            e is FormatException ? e.message : 'Connection test failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _save() async {
    await _testConnection();
    if (!mounted || _testSuccess != true) {
      return;
    }
    try {
      await AppConfig.setBackendBaseUrl(_controller.text);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _testMessage = 'Could not save the server address. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi, color: MeshColors.blue),
          SizedBox(width: 8),
          Text('Server (Over Wi-Fi)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the PC address on your phone’s Wi-Fi network. If the phone uses a PC hotspot, use the PC hotspot address. Changing servers signs you out so every service reconnects safely.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_isTesting,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {
                _testSuccess = null;
                _testMessage = null;
              }),
              decoration: const InputDecoration(
                labelText: 'Backend Server URL',
                hintText: 'http://PC-IP:8081',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_testSuccess == true ? Colors.green : Colors.red)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess == true ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess == true
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: _testSuccess == true ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _testSuccess == true
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check, size: 16),
              label: Text(
                  _isTesting ? 'Testing connection...' : 'Test Connection'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isTesting ? null : _save,
          child: const Text('Save & Apply'),
        ),
      ],
    );
  }
}
