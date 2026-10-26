import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ui/mesh_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/auth_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/services/user_service.dart';
import '../../../core/services/wifi_messaging_service.dart';
import '../../../core/services/wifi_file_transfer_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/wifi_peer_discovery_service.dart';
import '../../../core/services/webrtc_signaling_service.dart';
import '../../../core/services/call_service.dart';
import '../../call/screens/call_screen.dart';
import '../../call/models/call_session_state.dart';
import '../../../core/models/user.dart';
import '../../files/services/file_service.dart';
import '../../files/screens/file_list_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../friends/screens/friends_list_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../notes/screens/notes_screen.dart';
import '../../../core/security/e2e_encryption_service.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final bool isOfflineMode;

  const HomeScreen({
    super.key,
    required this.authService,
    this.isOfflineMode = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};

  late FriendService _friendService;
  late MessageService _messageService;
  late UserService _userService;
  late FileService _fileService;
  late E2eEncryptionService _e2eEncryptionService;

  late WifiPeerDiscoveryService _discoveryService;
  late WifiMessagingService _wifiMessagingService;
  late WifiFileTransferService _wifiFileTransferService;
  late RoutingService _routingService;
  late WebRtcSignalingService _webrtcSignalingService;
  late CallService _callService;
  StreamSubscription? _incomingCallSub;

  UserProfile? _currentUser;
  bool _isLoadingUser = true;
  bool _cloudSessionExpired = false;
  StreamSubscription<String>? _sessionSubscription;
  Timer? _sessionTimer;
  bool _reauthenticating = false;

  Future<void> _navigateToLogin() async {
    if (!mounted || _reauthenticating) return;
    _reauthenticating = true;
    await widget.authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(authService: widget.authService),
        ),
        (_) => false);
  }

  @override
  void initState() {
    super.initState();
    final jwt = widget.authService.jwtToken ?? '';
    final baseUrl = widget.authService.baseUrl;
    _sessionSubscription = AuthService.rejectedSessions.listen((token) {
      if (token == widget.authService.jwtToken && mounted) {
        setState(() {
          _cloudSessionExpired = true;
        });
      }
    });
    _sessionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final token = widget.authService.jwtToken;
      if (token != null && AuthService.tokenExpired(token) && mounted) {
        setState(() {
          _cloudSessionExpired = true;
        });
      }
    });

    _friendService = FriendService(baseUrl: baseUrl, jwtToken: jwt);
    _messageService = MessageService(baseUrl: baseUrl, jwtToken: jwt);
    _userService = UserService(baseUrl: baseUrl, jwtToken: jwt);
    _fileService = FileService(baseUrl: baseUrl, jwtToken: jwt);

    _discoveryService = WifiPeerDiscoveryService();

    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      UserProfile user;
      final jwt = widget.authService.jwtToken ?? '';
      final baseUrl = widget.authService.baseUrl;

      if (widget.isOfflineMode || jwt.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('cached_user_profile');
        if (cached != null) {
          user = UserProfile.fromJson(jsonDecode(cached));
        } else {
          user = await _userService.getMyProfile();
        }
      } else {
        try {
          user = await _userService.getMyProfile();
        } catch (e) {
          debugPrint('Remote profile load failed ($e). Falling back to cached profile.');
          final prefs = await SharedPreferences.getInstance();
          final cached = prefs.getString('cached_user_profile');
          if (cached != null) {
            user = UserProfile.fromJson(jsonDecode(cached));
          } else {
            rethrow;
          }
        }
      }

      // Initialize E2EE Service
      final e2ee = E2eEncryptionService(
        baseUrl: baseUrl,
        jwtToken: jwt,
        localOfflineMeshId: user.offlineMeshId,
      );
      await e2ee.initialize();
      _e2eEncryptionService = e2ee;
      _messageService.encryptionService = e2ee;
      _fileService.encryptionService = e2ee;
      if (jwt.isNotEmpty && !widget.isOfflineMode) {
        try {
          _messageService.connectStomp();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _currentUser = user;

          // Initialize WIFI_LAN services now that we have the current user
          _discoveryService.encryptionService = _e2eEncryptionService;

          _wifiMessagingService = WifiMessagingService(currentUser: user);
          _wifiMessagingService.initialize();

          _wifiFileTransferService = WifiFileTransferService(currentUser: user);
          _wifiFileTransferService.initialize();

          _routingService = RoutingService(
            messageService: _messageService,
            fileService: _fileService,
            wifiMessagingService: _wifiMessagingService,
            discoveryService: _discoveryService,
            wifiFileTransferService: _wifiFileTransferService,
            encryptionService: _e2eEncryptionService,
          );
          _routingService.initialize();

          _webrtcSignalingService = WebRtcSignalingService(
            jwtToken: widget.authService.jwtToken ?? '',
            localOfflineMeshId: user.offlineMeshId,
          );
          if (jwt.isNotEmpty && !widget.isOfflineMode) {
            try {
              _webrtcSignalingService.connect();
            } catch (_) {}
          }

          _callService = CallService(
            signalingService: _webrtcSignalingService,
            routingService: _routingService,
            localOfflineMeshId: user.offlineMeshId,
          );
          _callService.initialize();

          _incomingCallSub?.cancel();
          _incomingCallSub = _callService.callStateStream.listen((state) {
            if (state == CallSessionState.RINGING && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(callService: _callService),
                ),
              );
            }
          });

          _isLoadingUser = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load user profile: $e');
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _sessionTimer?.cancel();
    _discoveryService.stopDiscovery();
    if (_currentUser != null) {
      _wifiMessagingService.shutdown();
      _wifiFileTransferService.shutdown();
      _routingService.shutdown();
      _messageService.dispose();
      _webrtcSignalingService.dispose();
      _callService.dispose();
      _incomingCallSub?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser == null) {
      return const Scaffold(
          body: Center(child: Text('Failed to load profile. Please relogin.')));
    }

    final screens = [
      ChatListScreen(
        friendService: _friendService,
        messageService: _messageService,
        routingService: _routingService,
        callService: _callService,
      ),
      FriendsListScreen(friendService: _friendService),
      const NotesScreen(),
      FileListScreen(
          fileService: _fileService,
          routingService: _routingService,
          friendService: _friendService),
      ProfileScreen(userService: _userService, authService: widget.authService),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_cloudSessionExpired || widget.isOfflineMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF1E293B),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering_rounded,
                        size: 16, color: MeshColors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.isOfflineMode
                            ? 'Offline Mesh mode active'
                            : 'Server session expired. Offline Mesh active.',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _navigateToLogin,
                      child: const Text('Sign in',
                          style: TextStyle(
                              fontSize: 12,
                              color: MeshColors.orange,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: List.generate(screens.length,
                    (i) => TickerMode(
                      enabled: i == _currentIndex,
                      child: _visitedTabs.contains(i)
                          ? RepaintBoundary(child: screens[i])
                          : const SizedBox.shrink(),
                    )),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavigationBar(
        index: _currentIndex,
        onChanged: (index) {
          if (index == _currentIndex) return;
          setState(() {
            _visitedTabs.add(index);
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
