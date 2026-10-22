import 'package:flutter/material.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/ui/server_config_dialog.dart';

class RegisterScreen extends StatefulWidget {
  final AuthService authService;

  const RegisterScreen({super.key, required this.authService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Registration successful. Please log in.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AuthService.errorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Server Settings',
            onPressed: () {
              ServerConfigDialog.show(
                context,
                onSaved: () {
                  widget.authService.updateBaseUrl(AppConfig.backendBaseUrl);
                  if (mounted)
                    setState(() {
                      _errorMessage = null;
                    });
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (Optional)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _register,
                      child: const Text('Register'),
                    ),
                  ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                ServerConfigDialog.show(
                  context,
                  onSaved: () {
                    widget.authService.updateBaseUrl(AppConfig.backendBaseUrl);
                    if (mounted)
                      setState(() {
                        _errorMessage = null;
                      });
                  },
                );
              },
              icon: const Icon(Icons.wifi, size: 16),
              label: Text(
                'Server: ${widget.authService.baseUrl.replaceAll("http://", "")}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
