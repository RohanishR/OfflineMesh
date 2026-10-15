import 'package:flutter/material.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/services/friend_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/services/user_service.dart';
import '../../../core/services/wifi_messaging_service.dart';
import '../../../core/services/bluetooth_messaging_service.dart';
import '../../../core/services/wifi_file_transfer_service.dart';
import '../../../core/services/bluetooth_file_transfer_service.dart';
import '../../../core/services/ble_discovery_service.dart';
import '../../../core/services/ble_messaging_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/wifi_peer_discovery_service.dart';
import '../../../core/services/bluetooth_discovery_service.dart';
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
import '../../discovery/screens/nearby_devices_screen.dart';
import '../../../core/security/e2e_encryption_service.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;

  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late FriendService _friendService;
  late MessageService _messageService;
  late UserService _userService;
  late FileService _fileService;
  late E2eEncryptionService _e2eEncryptionService;
  
  late WifiPeerDiscoveryService _discoveryService;
  late BluetoothDiscoveryService _bluetoothDiscoveryService;
  
  late WifiMessagingService _wifiMessagingService;
  late BluetoothMessagingService _bluetoothMessagingService;
  
  late WifiFileTransferService _wifiFileTransferService;
  late BluetoothFileTransferService _bluetoothFileTransferService;
  late BleDiscoveryService _bleDiscoveryService;
  late BleMessagingService _bleMessagingService;
  late RoutingService _routingService;
  late WebRtcSignalingService _webrtcSignalingService;
  late CallService _callService;

  UserProfile? _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    final jwt = widget.authService.jwtToken ?? '';
    final baseUrl = widget.authService.baseUrl;
    
    _friendService = FriendService(baseUrl: baseUrl, jwtToken: jwt);
    _messageService = MessageService(baseUrl: baseUrl, jwtToken: jwt);
    _userService = UserService(baseUrl: baseUrl, jwtToken: jwt);
    _fileService = FileService(baseUrl: baseUrl, jwtToken: jwt);
    
    _discoveryService = WifiPeerDiscoveryService();
    _bluetoothDiscoveryService = BluetoothDiscoveryService();

    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _userService.getMyProfile();
      final jwt = widget.authService.jwtToken ?? '';
      final baseUrl = widget.authService.baseUrl;

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
      _messageService.connectStomp();

      if (mounted) {
        setState(() {
          _currentUser = user;
          
          // Initialize WIFI_LAN services now that we have the current user
          _discoveryService.encryptionService = _e2eEncryptionService;

          _wifiMessagingService = WifiMessagingService(currentUser: user);
          _wifiMessagingService.initialize();
          
          _bluetoothMessagingService = BluetoothMessagingService(
            currentUser: user,
            encryptionService: _e2eEncryptionService,
          );
          _bluetoothMessagingService.initialize();
          
          _wifiFileTransferService = WifiFileTransferService(currentUser: user);
          _wifiFileTransferService.initialize();
          
          _bluetoothFileTransferService = BluetoothFileTransferService(
            currentUser: user,
            bluetoothMessagingService: _bluetoothMessagingService,
          );
          _bluetoothFileTransferService.initialize();
          
          _bleDiscoveryService = BleDiscoveryService();
          _bleDiscoveryService.initialize();

          _bleMessagingService = BleMessagingService(
            currentUser: user,
            encryptionService: _e2eEncryptionService,
          );
          _bleMessagingService.initialize();
          
          _routingService = RoutingService(
            messageService: _messageService,
            fileService: _fileService,
            wifiMessagingService: _wifiMessagingService,
            discoveryService: _discoveryService,
            wifiFileTransferService: _wifiFileTransferService,
            bluetoothMessagingService: _bluetoothMessagingService,
            bluetoothFileTransferService: _bluetoothFileTransferService,
            bleDiscoveryService: _bleDiscoveryService,
            bleMessagingService: _bleMessagingService,
            encryptionService: _e2eEncryptionService,
          );
          _routingService.initialize();
          
          _webrtcSignalingService = WebRtcSignalingService(
            jwtToken: widget.authService.jwtToken ?? '',
            localOfflineMeshId: user.offlineMeshId,
          );
          _webrtcSignalingService.connect();
          
          _callService = CallService(
            signalingService: _webrtcSignalingService,
            routingService: _routingService,
            localOfflineMeshId: user.offlineMeshId,
          );
          _callService.initialize();
          
          _callService.callStateStream.listen((state) {
            if (state == CallSessionState.RINGING) {
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
    _discoveryService.stopDiscovery();
    _bluetoothDiscoveryService.dispose();
    if (_currentUser != null) {
      _wifiMessagingService.shutdown();
      _bluetoothMessagingService.shutdown();
      _wifiFileTransferService.shutdown();
      _bluetoothFileTransferService.shutdown();
      _bleDiscoveryService.shutdown();
      _bleMessagingService.shutdown();
      _routingService.shutdown();
      _messageService.dispose();
      _webrtcSignalingService.dispose();
      _callService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser == null) {
      return const Scaffold(body: Center(child: Text('Failed to load profile. Please relogin.')));
    }

    final screens = [
      ChatListScreen(
        friendService: _friendService, 
        messageService: _messageService, // Legacy list screen, could be updated if needed
        routingService: _routingService, // Passing routing service to ChatListScreen
        callService: _callService,
      ),
      FriendsListScreen(friendService: _friendService),
      NearbyDevicesScreen(
        currentUser: _currentUser!, 
        discoveryService: _discoveryService,
        bluetoothDiscoveryService: _bluetoothDiscoveryService,
        bleDiscoveryService: _bleDiscoveryService,
      ),
      FileListScreen(fileService: _fileService, routingService: _routingService, friendService: _friendService),
      ProfileScreen(userService: _userService, authService: widget.authService),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.wifi_tethering), label: 'Nearby'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
