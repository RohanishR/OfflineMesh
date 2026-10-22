import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'webrtc_signaling_service.dart';
import 'webrtc_call_service.dart';
import 'routing_service.dart';
import '../../core/transport/transport_type.dart';
import '../../features/call/models/webrtc_signaling_message.dart';
import '../../features/call/models/call_session_state.dart';
import '../config/app_config.dart';

class CallService {
  final WebRtcSignalingService signalingService;
  final RoutingService routingService;
  final String localOfflineMeshId;
  final List<Map<String, dynamic>>? customIceServers;

  WebRtcCallService? _webRtcCallService;
  MediaStream? localStream;
  MediaStream? remoteStream;
  bool _disposed = false;
  bool _isVideoCall = false;
  bool _isLocalWifiCall = false;

  CallSessionState _currentState = CallSessionState.IDLE;
  String? _currentSessionId;
  String? _remoteOfflineMeshId;

  Timer? _callTimeoutTimer;
  Timer? _reconnectTimeoutTimer;

  // Buffer ICE candidates that arrive before the peer connection is ready to process them
  final List<String> _iceCandidateBuffer = [];
  
  // Cache the incoming offer SDP while the user is deciding to answer
  String? _incomingOfferSdp;

  final _callStateController = StreamController<CallSessionState>.broadcast();
  Stream<CallSessionState> get callStateStream => _callStateController.stream;
  
  // Stream to notify UI of remote peer info
  final _remotePeerController = StreamController<String?>.broadcast();
  Stream<String?> get remotePeerStream => _remotePeerController.stream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;

  StreamSubscription? _signalingSubscription;
  StreamSubscription? _wifiSignalingSubscription;

  CallService({
    required this.signalingService,
    required this.routingService,
    required this.localOfflineMeshId,
    this.customIceServers,
  });

  void initialize() {
    _signalingSubscription = signalingService.incomingSignalingMessages.listen(_handleIncomingSignal);
    _wifiSignalingSubscription = routingService.wifiMessagingService.incomingSignalingMessages.listen((message) {
      _handleIncomingSignal(message, localWifi: true);
    });
  }

  void _setState(CallSessionState state) {
    if (_disposed || _currentState == state) return;
    _currentState = state;
    _callStateController.add(state);
    debugPrint('CallService state changed to: ${state.name}');
  }
  
  CallSessionState get currentState => _currentState;
  String? get remotePeerId => _remoteOfflineMeshId;
  bool get isVideoCall => _isVideoCall;
  bool get isLocalWifiCall => _isLocalWifiCall;

  void _handleIncomingSignal(WebRtcSignalingMessage message, {bool localWifi = false}) {
    if (_disposed || message.recipientOfflineMeshId != localOfflineMeshId) return;
    if (_currentSessionId == message.sessionId && _remoteOfflineMeshId != null &&
        message.senderOfflineMeshId != _remoteOfflineMeshId) return;
    if (_currentSessionId != null && message.sessionId != _currentSessionId) {
      if (message.type == 'CALL_OFFER') {
        _sendSignal(
          type: 'CALL_BUSY',
          recipientId: message.senderOfflineMeshId,
          sessionId: message.sessionId,
        );
      }
      return;
    }

    switch (message.type) {
      case 'CALL_OFFER':
        if (_currentState == CallSessionState.IDLE) {
          _currentSessionId = message.sessionId;
          _remoteOfflineMeshId = message.senderOfflineMeshId;
          _remotePeerController.add(_remoteOfflineMeshId);
          _iceCandidateBuffer.clear();
          _incomingOfferSdp = message.sdp;
          _isVideoCall = message.sdp?.contains('m=video') ?? false;
          _isLocalWifiCall = localWifi;
          _setState(CallSessionState.RINGING);
        }
        break;

      case 'CALL_ANSWER':
        if (_currentState == CallSessionState.CALLING) {
          if (message.sdp != null) {
            _setState(CallSessionState.NEGOTIATING);
            try {
              final sdpMap = jsonDecode(message.sdp!) as Map<String, dynamic>;
              _webRtcCallService?.setRemoteDescription(sdpMap).then((_) {
                _flushIceCandidates();
              });
            } catch (e) {
              debugPrint('Error applying CALL_ANSWER SDP: $e');
            }
          }
        }
        break;

      case 'ICE_CANDIDATE':
        if (message.iceCandidate != null) {
          if (_currentState == CallSessionState.NEGOTIATING || _currentState == CallSessionState.CONNECTED) {
            try {
              final candidateMap = jsonDecode(message.iceCandidate!) as Map<String, dynamic>;
              _webRtcCallService?.addIceCandidate(candidateMap);
            } catch (e) {
              debugPrint('Error applying ICE candidate: $e');
            }
          } else {
            _iceCandidateBuffer.add(message.iceCandidate!);
          }
        }
        break;

      case 'CALL_REJECT':
        _cleanupCall();
        _setState(CallSessionState.REJECTED);
        _resetToIdleAfterDelay();
        break;

      case 'CALL_BUSY':
        _cleanupCall();
        _setState(CallSessionState.BUSY);
        _resetToIdleAfterDelay();
        break;
        
      case 'CALL_CANCEL':
        _cleanupCall();
        _setState(CallSessionState.CANCELLED);
        _resetToIdleAfterDelay();
        break;
        
      case 'CALL_END':
        _cleanupCall();
        _setState(CallSessionState.ENDED);
        _resetToIdleAfterDelay();
        break;
        
      case 'CALL_FAILED':
        _cleanupCall();
        _setState(CallSessionState.FAILED);
        _resetToIdleAfterDelay();
        break;
    }
  }

  void _resetToIdleAfterDelay() {
    Future.delayed(const Duration(seconds: 2), () {
      if (_currentState == CallSessionState.ENDED || 
          _currentState == CallSessionState.REJECTED || 
          _currentState == CallSessionState.CANCELLED || 
          _currentState == CallSessionState.FAILED ||
          _currentState == CallSessionState.BUSY) {
        _setState(CallSessionState.IDLE);
      }
    });
  }

  void _flushIceCandidates() {
    for (final candidateStr in _iceCandidateBuffer) {
      try {
        final candidateMap = jsonDecode(candidateStr) as Map<String, dynamic>;
        _webRtcCallService?.addIceCandidate(candidateMap);
      } catch (e) {
        debugPrint('Error applying buffered ICE candidate: $e');
      }
    }
    _iceCandidateBuffer.clear();
  }

  Future<void> _initWebRtcCallService({required bool isCaller}) async {
    // When operating completely offline on local Wi-Fi, omit external STUN servers to avoid DNS timeouts
    final iceServersToUse = (_isLocalWifiCall && !signalingService.isConnected)
        ? <Map<String, dynamic>>[]
        : (customIceServers ?? AppConfig.defaultIceServers);

    _webRtcCallService = WebRtcCallService(
      customIceServers: iceServersToUse,
      onLocalSdpGenerated: (sdpStr) {
        if (_disposed || _currentSessionId == null || _remoteOfflineMeshId == null) return;
        // Send the offer or answer
        if (isCaller) {
          _sendSignal(
            type: 'CALL_OFFER',
            recipientId: _remoteOfflineMeshId!,
            sessionId: _currentSessionId!,
            sdp: sdpStr,
          );
        } else {
          _sendSignal(
            type: 'CALL_ANSWER',
            recipientId: _remoteOfflineMeshId!,
            sessionId: _currentSessionId!,
            sdp: sdpStr,
          );
        }
      },
      onLocalIceCandidateGenerated: (candidateStr) {
        if (_disposed || _currentSessionId == null || _remoteOfflineMeshId == null) return;
        _sendSignal(
          type: 'ICE_CANDIDATE',
          recipientId: _remoteOfflineMeshId!,
          sessionId: _currentSessionId!,
          iceCandidate: candidateStr,
        );
      },
      onIceConnectionState: (state) {
        if (_disposed || _currentSessionId == null) return;
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _callTimeoutTimer?.cancel();
          _callTimeoutTimer = null;
          _reconnectTimeoutTimer?.cancel();
          _reconnectTimeoutTimer = null;
          _setState(CallSessionState.CONNECTED);
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _setState(CallSessionState.RECONNECTING);

          // If Internet dropped during call but peer is nearby on Wi-Fi, fall back to local Wi-Fi signaling
          if (!_isLocalWifiCall && _remoteOfflineMeshId != null && routingService.isPeerNearby(_remoteOfflineMeshId!)) {
            debugPrint('Internet call disconnected; falling back to local Wi-Fi direct calling.');
            _isLocalWifiCall = true;
          }

          _reconnectTimeoutTimer?.cancel();
          _reconnectTimeoutTimer = Timer(const Duration(seconds: 15), () {
            if (_currentState == CallSessionState.RECONNECTING) {
              debugPrint('Reconnection timed out. Ending call.');
              endCall();
            }
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                   state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          endCall();
        }
      },
      onLocalStreamAdded: (stream) {
        if (_disposed || _currentSessionId == null) return;
        localStream = stream;
        _localStreamController.add(stream);
      },
      onRemoteStreamAdded: (stream) {
        if (_disposed || _currentSessionId == null) return;
        remoteStream = stream;
        _remoteStreamController.add(stream);
      },
    );

    try {
      final actualIsVideo = await _webRtcCallService!.initializeConnection(isCaller: isCaller, isVideoCall: _isVideoCall);
      if (_isVideoCall && !actualIsVideo) {
        _isVideoCall = false;
        _callStateController.add(_currentState);
      }
    } catch (e) {
      debugPrint('Failed to initialize WebRTC Call Service: $e');
      endCall();
    }
  }

  // --- Call Routing API ---

  List<TransportType> getAvailableCallTransports(String destId) {
    final routes = <TransportType>[];
    if (routingService.isPeerNearby(destId)) {
      routes.add(TransportType.WIFI_LAN);
    }
    if (signalingService.isConnected) {
      routes.add(TransportType.INTERNET);
    }
    return routes;
  }

  bool canStartCall(String destId) {
    return getAvailableCallTransports(destId).isNotEmpty;
  }

  // --- API for UI ---

  void initiateCall(String recipientId, {bool isVideoCall = false}) {
    if (_currentState != CallSessionState.IDLE) return;
    
    final routes = getAvailableCallTransports(recipientId);
    if (routes.isEmpty) {
      debugPrint('No available transports to start call.');
      return;
    }
    
    _currentSessionId = const Uuid().v4();
    _remoteOfflineMeshId = recipientId;
    _remotePeerController.add(_remoteOfflineMeshId);
    _iceCandidateBuffer.clear();
    _isVideoCall = isVideoCall;
    _isLocalWifiCall = routes.contains(TransportType.WIFI_LAN);
    
    _setState(CallSessionState.CALLING);

    // Call timeout: if not answered within 30 seconds, cancel call
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_currentState == CallSessionState.CALLING || _currentState == CallSessionState.NEGOTIATING) {
        debugPrint('Call offer timed out waiting for answer.');
        endCall();
      }
    });

    _initWebRtcCallService(isCaller: true);
  }

  void acceptCall() async {
    if (_currentState != CallSessionState.RINGING || _remoteOfflineMeshId == null) return;
    
    _setState(CallSessionState.ACCEPTED);
    await _initWebRtcCallService(isCaller: false);
    
    if (_incomingOfferSdp != null) {
      try {
        final sdpMap = jsonDecode(_incomingOfferSdp!) as Map<String, dynamic>;
        await _webRtcCallService?.setRemoteDescription(sdpMap);
        await _webRtcCallService?.createAnswer();
        
        _setState(CallSessionState.NEGOTIATING);
        _flushIceCandidates();
      } catch (e) {
        debugPrint('Error applying CALL_OFFER SDP during accept: $e');
      }
    }
  }

  void rejectCall() {
    if (_currentState != CallSessionState.RINGING || _remoteOfflineMeshId == null) return;
    _sendSignal(
      type: 'CALL_REJECT',
      recipientId: _remoteOfflineMeshId!,
      sessionId: _currentSessionId!,
    );
    _cleanupCall();
    _setState(CallSessionState.IDLE);
  }

  void endCall() {
    if (_remoteOfflineMeshId != null && _currentSessionId != null) {
      // If we are CALLING, and we end, it's a CANCEL
      if (_currentState == CallSessionState.CALLING) {
        _sendSignal(
          type: 'CALL_CANCEL',
          recipientId: _remoteOfflineMeshId!,
          sessionId: _currentSessionId!,
        );
      } else {
        _sendSignal(
          type: 'CALL_END',
          recipientId: _remoteOfflineMeshId!,
          sessionId: _currentSessionId!,
        );
      }
    }
    _cleanupCall();
    _setState(CallSessionState.ENDED);
    _resetToIdleAfterDelay();
  }
  
  void toggleMute(bool isMuted) {
    _webRtcCallService?.toggleMute(isMuted);
  }

  void toggleVideo(bool isEnabled) {
    _webRtcCallService?.toggleVideo(isEnabled);
  }

  void switchCamera() {
    _webRtcCallService?.switchCamera();
  }

  void setSpeakerphone(bool enable) {
    _webRtcCallService?.setSpeakerphone(enable);
  }

  void _sendSignal({
    required String type,
    required String recipientId,
    required String sessionId,
    String? sdp,
    String? iceCandidate,
  }) {
    final message = WebRtcSignalingMessage(
      id: const Uuid().v4(),
      sessionId: sessionId,
      senderOfflineMeshId: localOfflineMeshId,
      recipientOfflineMeshId: recipientId,
      type: type,
      sdp: sdp,
      iceCandidate: iceCandidate,
      timestamp: DateTime.now(),
    );

    // If active call is local Wi-Fi call or nearby peer exists while Internet signaling is down
    if (_isLocalWifiCall || (routingService.isPeerNearby(recipientId) && !signalingService.isConnected)) {
      final peer = routingService.getNearbyPeer(recipientId);
      if (peer != null) {
        routingService.wifiMessagingService.sendSignalingMessage(peer, message).catchError((e) {
          debugPrint('Local Wi-Fi signaling send failed, falling back to Internet: $e');
          signalingService.sendSignalingMessage(message);
        });
        return;
      }
    }

    signalingService.sendSignalingMessage(message);
  }

  Future<void> _cleanupCall() async {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _reconnectTimeoutTimer?.cancel();
    _reconnectTimeoutTimer = null;

    _currentSessionId = null;
    _remoteOfflineMeshId = null;
    _remotePeerController.add(null);
    _incomingOfferSdp = null;
    _iceCandidateBuffer.clear();
    
    localStream = null;
    remoteStream = null;
    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _isVideoCall = false;
    _isLocalWifiCall = false;
    
    if (_webRtcCallService != null) {
      await _webRtcCallService!.dispose();
      _webRtcCallService = null;
    }
  }

  void dispose() {
    _disposed = true;
    _cleanupCall();
    _signalingSubscription?.cancel();
    _wifiSignalingSubscription?.cancel();
    _callStateController.close();
    _remotePeerController.close();
    _localStreamController.close();
    _remoteStreamController.close();
  }
}
