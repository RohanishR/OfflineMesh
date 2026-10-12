import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/discovered_peer.dart';
import '../models/user.dart';

class WifiPeerDiscoveryService {
  static const int _discoveryPort = 45454;
  static const Duration _broadcastInterval = Duration(seconds: 3);
  static const Duration _peerTimeout = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final Map<String, DiscoveredPeer> _peers = {};
  
  // Stream to notify UI of changes
  final _peersController = StreamController<List<DiscoveredPeer>>.broadcast();
  Stream<List<DiscoveredPeer>> get peersStream => _peersController.stream;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  Future<void> startDiscovery(UserProfile currentUser) async {
    if (_isDiscovering) return;
    
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
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
  }

  void _broadcastPresence(UserProfile currentUser) {
    if (_socket == null) return;
    
    final payload = {
      'offlineMeshId': currentUser.offlineMeshId,
      'displayName': currentUser.username,
      'deviceId': currentUser.offlineMeshId, // using OfflineMeshId as device ID for now
      'port': _discoveryPort,
      'protocolVersion': 1,
    };
    
    final data = utf8.encode(jsonEncode(payload));
    
    try {
      _socket!.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (e) {
      debugPrint('Error sending UDP broadcast: $e');
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
