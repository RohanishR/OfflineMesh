import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/services/user_service.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/models/user.dart';
import '../../../core/security/e2e_encryption_service.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserService userService;
  final AuthService authService;

  const ProfileScreen({super.key, required this.userService, required this.authService});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  String? _fingerprint;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await widget.userService.getMyProfile();
      String? fp;
      try {
        const secureStorage = FlutterSecureStorage();
        final pubKeyBase64 = await secureStorage.read(key: 'e2ee_pub_${response.offlineMeshId}');
        if (pubKeyBase64 != null) {
          fp = await E2eEncryptionService.computeFingerprint(base64Decode(pubKeyBase64));
        }
      } catch (e) {
        debugPrint('Could not compute fingerprint: $e');
      }

      setState(() {
        _profile = response;
        _fingerprint = fp;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyId() {
    if (_profile != null) {
      Clipboard.setData(ClipboardData(text: _profile!.offlineMeshId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OfflineMesh ID copied to clipboard')),
      );
    }
  }

  void _copyFingerprint() {
    if (_fingerprint != null) {
      Clipboard.setData(ClipboardData(text: _fingerprint!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E2EE Fingerprint copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text('Error: $_errorMessage'));
    }

    if (_profile == null) {
      return const Center(child: Text('No profile data'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    authService: widget.authService,
                  ),
                ),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 40,
              child: Icon(Icons.person, size: 40),
            ),
            const SizedBox(height: 24),
            Text('Username', style: Theme.of(context).textTheme.titleSmall),
            Text(_profile!.username, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_profile!.email != null) ...[
              Text('Email', style: Theme.of(context).textTheme.titleSmall),
              Text(_profile!.email!, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
            ],
            Text('OfflineMesh ID', style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Text(_profile!.offlineMeshId, style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copyId,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('E2EE Security Fingerprint', style: Theme.of(context).textTheme.titleSmall),
            if (_fingerprint != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fingerprint!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: _copyFingerprint,
                  ),
                ],
              )
            else
              const Text('Not initialized', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
