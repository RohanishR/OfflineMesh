import '../../../core/ui/mesh_widgets.dart';
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

  const ProfileScreen(
      {super.key, required this.userService, required this.authService});

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.userService.getMyProfile();
      String? fp;
      try {
        const secureStorage = FlutterSecureStorage();
        final pubKeyBase64 =
            await secureStorage.read(key: 'e2ee_pub_${response.offlineMeshId}');
        if (pubKeyBase64 != null) {
          fp = await E2eEncryptionService.computeFingerprint(
              base64Decode(pubKeyBase64));
        }
      } catch (e) {
        debugPrint('Could not compute fingerprint: $e');
      }

      if (!mounted) return;
      setState(() {
        _profile = response;
        _fingerprint = fp;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _rotateKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: MeshColors.orange),
            SizedBox(width: 8),
            Text('Rotate Identity Key?'),
          ],
        ),
        content: const Text(
          'Generating a new identity key will change your cryptographic safety number. '
          'Your existing contacts will see a "Security Code Changed" notice on their next message.\n\n'
          'Are you sure you want to rotate your key pair now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MeshColors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rotate Key'),
          ),
        ],
      ),
    );

    if (confirmed != true || _profile == null) return;

    try {
      final e2ee = E2eEncryptionService(
        baseUrl: widget.authService.baseUrl,
        jwtToken: widget.authService.jwtToken ?? '',
        localOfflineMeshId: _profile!.offlineMeshId,
      );
      await e2ee.initialize();
      final newFp = await e2ee.rotateIdentityKeyPair();
      if (mounted) {
        setState(() {
          _fingerprint = newFp;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identity key successfully rotated and registered.'),
            backgroundColor: Color(0xFF25D366),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rotate key: $e')),
        );
      }
    }
  }

  void _settings() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(authService: widget.authService)));
  @override
  Widget build(BuildContext context) => MeshPage(
        title: 'Profile',
        subtitle: 'Your place in the mesh.',
        actions: [
          IconButton(
              tooltip: 'Settings',
              onPressed: _settings,
              icon: const Icon(Icons.settings_outlined))
        ],
        child: _isLoading
            ? const LoadingStateView()
            : _errorMessage != null || _profile == null
                ? EmptyStateView(
                    icon: Icons.person_off_outlined,
                    title: 'Profile unavailable',
                    message: 'We couldn’t load your account. Please try again.',
                    onAction: _loadProfile)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                        GlassSurface(
                            child: Column(children: [
                          MeshAvatar(name: _profile!.username, size: 88),
                          const SizedBox(height: 18),
                          Text(_profile!.username,
                              textAlign: TextAlign.center,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          if (_profile!.email != null) ...[
                            const SizedBox(height: 6),
                            Text(_profile!.email!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall)
                          ],
                        ])),
                        const SizedBox(height: 24),
                        Text('YOUR IDENTITY',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.8,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 12),
                        GlassSurface(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                const Icon(Icons.fingerprint_rounded),
                                const SizedBox(width: 10),
                                const Expanded(child: Text('OfflineMesh ID')),
                                IconButton(
                                    tooltip: 'Copy OfflineMesh ID',
                                    onPressed: _copyId,
                                    icon: const Icon(Icons.copy_rounded))
                              ]),
                              const SizedBox(height: 8),
                              SelectableText(_profile!.offlineMeshId,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 16,
                                      height: 1.6)),
                              const SizedBox(height: 12),
                              Text('Share this ID so friends can find you.',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ])),
                        const SizedBox(height: 16),
                        GlassSurface(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                const Icon(Icons.shield_outlined),
                                const SizedBox(width: 10),
                                const Expanded(
                                    child: Text('Security fingerprint')),
                                if (_fingerprint != null)
                                  IconButton(
                                      tooltip: 'Copy fingerprint',
                                      onPressed: _copyFingerprint,
                                      icon: const Icon(Icons.copy_rounded))
                              ]),
                              const SizedBox(height: 16),
                              SelectableText(_fingerprint ?? 'Not initialized',
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      height: 1.8,
                                      letterSpacing: .6)),
                              const SizedBox(height: 14),
                              Text(
                                  'Compare fingerprints with a friend through a trusted channel. A fingerprint alone does not verify a contact.',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.sync_lock_rounded, size: 18),
                                label: const Text('Rotate Identity Key Pair'),
                                onPressed: _rotateKey,
                              ),
                            ])),
                        const SizedBox(height: 16),
                        GlassSurface(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                                leading: const Icon(Icons.tune_rounded),
                                title: const Text('Make it yours'),
                                subtitle: const Text('Appearance & account'),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: _settings)),
                      ]),
      );
}
