import '../../../core/ui/mesh_widgets.dart';
import 'package:flutter/material.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/ui/server_config_dialog.dart';
import '../../home/screens/home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(authService: widget.authService),
        ),
      );
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
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: Center(
                  child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: MeshColors.navy,
                      borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.hub_outlined,
                      size: 36, color: Colors.white)),
              const SizedBox(height: 28),
              const Text('OFFLINEMESH',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('Closer, even\nfrom here.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontSize: 40)),
              const SizedBox(height: 14),
              Text('Welcome back. Sign in to your connections.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 36),
              GlassSurface(
                  child: Column(children: [
                TextField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 16),
                TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) {
                      if (!_isLoading) _login();
                    },
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline))),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                      liveRegion: true,
                      child: Text(
                          'Couldn’t sign in. Check your connection and credentials, then try again.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)))
                ],
                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: MeshColors.orange,
                            foregroundColor: MeshColors.midnight),
                        onPressed: _isLoading ? null : _login,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(_isLoading ? 'Signing in…' : 'Sign in'))),
              ])),
              const SizedBox(height: 20),
              Center(
                  child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => RegisterScreen(
                                  authService: widget.authService))),
                      child: const Text('New here? Create an account'))),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    ServerConfigDialog.show(
                      context,
                      onSaved: () {
                        widget.authService
                            .updateBaseUrl(AppConfig.backendBaseUrl);
                        if (mounted) {
                          setState(() {
                            _errorMessage = null;
                          });
                        }
                      },
                    );
                  },
                  icon: const Icon(Icons.wifi, size: 16),
                  label: Text(
                    'Server: ${AppConfig.backendBaseUrl.replaceAll("http://", "")}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ])),
      ))));
}
