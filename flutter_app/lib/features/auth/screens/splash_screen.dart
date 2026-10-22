import 'package:flutter/material.dart';
import '../../../core/network/auth_service.dart';
import '../../home/screens/home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  final AuthService authService;

  const SplashScreen({super.key, required this.authService});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await widget.authService.init();

    if (!mounted) return;

    if (widget.authService.isAuthenticated) {
      try {
        await widget.authService.me();
      } catch (e) {
        debugPrint('Could not reach backend on startup (offline mode): $e');
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(authService: widget.authService),
          ),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(authService: widget.authService),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
