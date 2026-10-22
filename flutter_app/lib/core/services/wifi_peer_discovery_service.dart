import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/discovered_peer.dart';
import '../models/user.dart';
import '../security/e2e_encryption_service.dart';

class WifiPeerDiscoveryService {
  static const int _discoveryPort = 45454;
  static const Duration _broadcastInterval = Duration(seconds: 3);
  static const Duration _peerTimeout = Duration(seconds: 10);
  static const MethodChannel _multicastChannel = MethodChannel('com.offlinemesh/wifi_multicast');

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final Map<String, DiscoveredPeer> _peers = {};
  
  // Stream to notify UI of changes
  final _peersController = StreamController<List<DiscoveredPeer>>.broadcast();
  Stream<List<DiscoveredPeer>> get peersStream => _peersController.stream;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  E2eEncryptionService? encryptionService;

  WifiPeerDiscoveryService({this.encryptionService});

  Future<void> startDiscovery(UserProfile currentUser) async {
    if (_isDiscovering) return;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('acquireMulticastLock');
      } catch (e) {
        debugPrint('Could not acquire multicast lock: $e');
      }
    }
    
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket!.broadcastEnabled = true;
      _isDiscovering = true;

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _socket!.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram, currentUser);
          }
        }
      });

      _broadcastTimer = Timer.periodic(_broadcastInterval, (_) {
        _broadcastPresence(currentUser);
      });

      _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _removeStalePeers();
      });
      
    } catch (e) {
      debugPrint('Error starting Wi-Fi Discovery: $e');
      _isDiscovering = false;
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _multicastChannel.invokeMethod('releaseMulticastLock');
        } catch (_) {}
      }
    }
  }

  void stopDiscovery() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    
    _socket = null;
    _isDiscovering = false;
    _peers.clear();
    _notifyListeners();

    if (!kIsWeb && Platform.isAndroid) {
      try {
        _multicastChannel.invokeMethod('releaseMulticastLock');
      } catch (e) {
        debugPrint('Could not release multicast lock: $e');
      }
    }
  }

  List<String> _activeIps = [];
  List<String> get activeIps => List.unmodifiable(_activeIps);
  bool get hasLocalWifiOrHotspot => _activeIps.any((ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.'));

  Future<void> _broadcastPresence(UserProfile currentUser) async {
    if (_socket == null) return;
    
    final payload = <String, dynamic>{
      'offlineMeshId': currentUser.offlineMeshId,
      'displayName': currentUser.username,
      'deviceId': currentUser.offlineMeshId,
      'port': 45455,
      'protocolVersion': 1,
    };

    if (encryptionService != null) {
      final pubKey = encryptionService!.identityPublicKeyBase64;
      if (pubKey != null) {
        payload['publicKey'] = pubKey;
        payload['keyId'] = encryptionService!.identityKeyId;
        payload['fingerprint'] = encryptionService!.fingerprint;
      }
    }
    
    final data = utf8.encode(jsonEncode(payload));
    
    // 1. Send to global broadcast address
    try {
      _socket?.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (e) {
      debugPrint('Error sending UDP global broadcast: $e');
    }

    // 2. Send to specific subnet broadcast address for each active network interface
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final currentIps = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          currentIps.add(addr.address);
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              _socket?.send(data, InternetAddress(subnetBroadcast), _discoveryPort);
            } catch (_) {}
          }
        }
      }
      _activeIps = currentIps;

      // 3. Android Hotspot special handling: If client is connected to hotspot (192.168.43.x),
      // also ping the hotspot host gateway directly at 192.168.43.1 in case router drops broadcast.
      for (final ip in currentIps) {
        if (ip.startsWith('192.168.43.') && ip != '192.168.43.1') {
          try {
            _socket?.send(data, InternetAddress('192.168.43.1'), _discoveryPort);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error sending subnet broadcast: $e');
    }
  }

  void _handleIncomingDatagram(Datagram datagram, UserProfile currentUser) {
    try {
      final String message = utf8.decode(datagram.data);
      final Map<String, dynamic> payload = jsonDecode(message);
      
      final offlineMeshId = payload['offlineMeshId'] as String?;
      
      // Ignore our own broadcasts
      if (offlineMeshId == null || offlineMeshId == currentUser.offlineMeshId) {
        return;
      }
      
      final displayName = payload['displayName'] as String? ?? 'Unknown';
      final deviceId = payload['deviceId'] as String? ?? offlineMeshId;
      final port = payload['port'] as int? ?? _discoveryPort;

      final remotePubKey = payload['publicKey'] as String?;
      final remoteKeyId = payload['keyId'] as String?;
      final remoteFingerprint = payload['fingerprint'] as String?;

      if (remotePubKey != null && remoteKeyId != null && encryptionService != null) {
        encryptionService!.registerPeerKey(
          offlineMeshId: offlineMeshId,
          publicKeyBase64: remotePubKey,
          keyId: remoteKeyId,
          fingerprint: remoteFingerprint,
        );
      }
      
      final now = DateTime.now();
      
      if (_peers.containsKey(offlineMeshId)) {
        _peers[offlineMeshId]!.lastSeenTimestamp = now;
        _peers[offlineMeshId]!.isReachable = true;
      } else {
        final newPeer = DiscoveredPeer(
          offlineMeshId: offlineMeshId,
          displayName: displayName,
          deviceId: deviceId,
          ipAddress: datagram.address.address,
          port: port,
          discoveryTimestamp: now,
          lastSeenTimestamp: now,
        );
        _peers[offlineMeshId] = newPeer;
        _notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to parse incoming UDP datagram: $e');
    }
  }

  void _removeStalePeers() {
    final now = DateTime.now();
    bool changed = false;
    
    _peers.removeWhere((id, peer) {
      if (now.difference(peer.lastSeenTimestamp) > _peerTimeout) {
        changed = true;
        return true;
      }
      return false;
    });
    
    if (changed) {
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    _peersController.add(_peers.values.toList());
  }
}
