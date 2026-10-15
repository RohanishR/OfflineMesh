import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcCallService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final void Function(String sdp)? onLocalSdpGenerated;
  final void Function(String iceCandidate)? onLocalIceCandidateGenerated;
  final void Function(RTCIceConnectionState state)? onIceConnectionState;
  final void Function(MediaStream stream)? onLocalStreamAdded;
  final void Function(MediaStream stream)? onRemoteStreamAdded;

  WebRtcCallService({
    this.onLocalSdpGenerated,
    this.onLocalIceCandidateGenerated,
    this.onIceConnectionState,
    this.onLocalStreamAdded,
    this.onRemoteStreamAdded,
  });

  /// The STUN/TURN configuration
  Map<String, dynamic> _getIceServers() {
    return {
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302'
          ]
        },
        // Placeholder for TURN configuration in the future
      ]
    };
  }

  /// Initialize the peer connection and capture local media
  Future<bool> initializeConnection({required bool isCaller, required bool isVideoCall}) async {
    _peerConnection = await createPeerConnection(_getIceServers());

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (onLocalIceCandidateGenerated != null) {
        onLocalIceCandidateGenerated!(jsonEncode(candidate.toMap()));
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('ICE Connection State: $state');
      if (onIceConnectionState != null) {
        onIceConnectionState!(state);
      }
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('Remote stream added. Audio tracks: ${stream.getAudioTracks().length}, Video tracks: ${stream.getVideoTracks().length}');
      if (onRemoteStreamAdded != null) {
        onRemoteStreamAdded!(stream);
      }
    };

    final actualIsVideo = await _captureLocalMedia(isVideoCall: isVideoCall);
    
    if (_localStream != null) {
      await _peerConnection!.addStream(_localStream!);
    }

    if (isCaller) {
      await _createOffer();
    }
    
    return actualIsVideo;
  }

  Future<bool> _captureLocalMedia({required bool isVideoCall}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideoCall ? {
        'mandatory': {
          'minWidth': '640', 
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      } : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      debugPrint('Local media stream captured. Video: $isVideoCall');
      if (onLocalStreamAdded != null) {
        onLocalStreamAdded!(_localStream!);
      }
      return isVideoCall;
    } catch (e) {
      debugPrint('Failed to capture local media with video (permissions?): $e');
      if (isVideoCall) {
        debugPrint('Falling back to audio-only capture.');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
          debugPrint('Local media stream captured (audio-only fallback).');
          if (onLocalStreamAdded != null) {
            onLocalStreamAdded!(_localStream!);
          }
          return false; // Indicates we fell back to audio
        } catch (fallbackError) {
          debugPrint('Failed to capture audio during fallback: $fallbackError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null) return;
    try {
      final RTCSessionDescription description = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(description);
      
      if (onLocalSdpGenerated != null) {
        onLocalSdpGenerated!(jsonEncode(description.toMap()));
      }
    } catch (e) {
      debugPrint('Failed to create SDP offer: $e');
    }
  }

  Future<void> createAnswer() async {
    if (_peerConnection == null) return;
    try {
      final RTCSessionDescription description = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(description);
      
      if (onLocalSdpGenerated != null) {
        onLocalSdpGenerated!(jsonEncode(description.toMap()));
      }
    } catch (e) {
      debugPrint('Failed to create SDP answer: $e');
    }
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    if (_peerConnection == null) return;
    try {
      final String type = sdpMap['type'] as String;
      final String sdp = sdpMap['sdp'] as String;
      final RTCSessionDescription description = RTCSessionDescription(sdp, type);
      await _peerConnection!.setRemoteDescription(description);
    } catch (e) {
      debugPrint('Failed to set remote description: $e');
    }
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidateMap) async {
    if (_peerConnection == null) return;
    try {
      final String? candidate = candidateMap['candidate'];
      final String? sdpMid = candidateMap['sdpMid'];
      final int? sdpMLineIndex = candidateMap['sdpMLineIndex'];
      
      final RTCIceCandidate rtcCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      await _peerConnection!.addCandidate(rtcCandidate);
    } catch (e) {
      debugPrint('Failed to add remote ICE candidate: $e');
    }
  }

  void toggleMute(bool isMuted) {
    if (_localStream == null) return;
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      audioTracks[0].enabled = !isMuted;
    }
  }

  void toggleVideo(bool isEnabled) {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      videoTracks[0].enabled = isEnabled;
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks[0]);
    }
  }

  Future<void> dispose() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }
      
      if (_peerConnection != null) {
        await _peerConnection!.close();
        await _peerConnection!.dispose();
        _peerConnection = null;
      }
    } catch (e) {
      debugPrint('Error disposing WebRtcCallService: $e');
    }
  }
}
