import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/services/call_service.dart';
import '../models/call_session_state.dart';

class CallScreen extends StatefulWidget {
  final CallService callService;

  const CallScreen({Key? key, required this.callService}) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallSessionState _currentState = CallSessionState.IDLE;
  String? _remotePeerId;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  Timer? _durationTimer;
  int _secondsElapsed = 0;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _localStreamSub;
  StreamSubscription? _remoteStreamSub;

  @override
  void initState() {
    super.initState();
    _currentState = widget.callService.currentState;
    _remotePeerId = widget.callService.remotePeerId;

    _initRenderers();

    widget.callService.callStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _currentState = state;
        });
        
        if (state == CallSessionState.CONNECTED && _durationTimer == null) {
          _startDurationTimer();
        } else if (state == CallSessionState.ENDED || 
                   state == CallSessionState.REJECTED || 
                   state == CallSessionState.CANCELLED ||
                   state == CallSessionState.FAILED ||
                   state == CallSessionState.IDLE) {
          _stopDurationTimer();
          
          if (state == CallSessionState.IDLE && mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    });

    widget.callService.remotePeerStream.listen((peerId) {
      if (mounted) {
        setState(() {
          _remotePeerId = peerId;
        });
      }
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _localStreamSub = widget.callService.localStreamStream.listen((stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    });

    _remoteStreamSub = widget.callService.remoteStreamStream.listen((stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    });
  }

  void _startDurationTimer() {
    _secondsElapsed = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopDurationTimer();
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    widget.callService.toggleMute(_isMuted);
  }

  void _toggleVideo() {
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
    });
    widget.callService.toggleVideo(_isVideoEnabled);
  }

  void _switchCamera() {
    widget.callService.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    final isVideoCall = widget.callService.isVideoCall;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video Background
            if (isVideoCall && _remoteRenderer.srcObject != null && _currentState == CallSessionState.CONNECTED)
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                    if (widget.callService.isLocalWifiCall)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi, color: Colors.greenAccent, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Connected via Wi-Fi',
                                style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              // Audio Call UI or Pre-connection UI
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blueGrey,
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _remotePeerId ?? 'Unknown Peer',
                      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _currentState.name,
                      style: const TextStyle(fontSize: 18, color: Colors.white70),
                    ),
                    if (_currentState == CallSessionState.CALLING || _currentState == CallSessionState.RINGING) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.callService.isLocalWifiCall ? 'Calling via Wi-Fi' : 'Calling via Internet',
                        style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                    if (_currentState == CallSessionState.CONNECTED) ...[
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_secondsElapsed),
                        style: const TextStyle(fontSize: 16, color: Colors.white54),
                      ),
                      if (widget.callService.isLocalWifiCall) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Connected via Wi-Fi',
                          style: TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

            // Local Video Picture-in-Picture
            if (isVideoCall && _localRenderer.srcObject != null)
              Positioned(
                top: 16,
                right: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black54,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // Controls
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_currentState == CallSessionState.RINGING) ...[
                    // Reject Button
                    FloatingActionButton(
                      heroTag: 'reject',
                      backgroundColor: Colors.red,
                      onPressed: () => widget.callService.rejectCall(),
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    // Accept Button
                    FloatingActionButton(
                      heroTag: 'accept',
                      backgroundColor: Colors.green,
                      onPressed: () => widget.callService.acceptCall(),
                      child: const Icon(Icons.call, color: Colors.white),
                    ),
                  ] else if (_currentState != CallSessionState.IDLE) ...[
                    // Camera Switch (only for video)
                    if (isVideoCall)
                      FloatingActionButton(
                        heroTag: 'switch_cam',
                        backgroundColor: Colors.white24,
                        onPressed: _switchCamera,
                        child: const Icon(Icons.cameraswitch, color: Colors.white),
                      ),
                    // Camera Toggle (only for video)
                    if (isVideoCall)
                      FloatingActionButton(
                        heroTag: 'toggle_video',
                        backgroundColor: _isVideoEnabled ? Colors.white24 : Colors.white,
                        onPressed: _toggleVideo,
                        child: Icon(
                          _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                          color: _isVideoEnabled ? Colors.white : Colors.black,
                        ),
                      ),
                    // Mute Button
                    FloatingActionButton(
                      heroTag: 'mute',
                      backgroundColor: _isMuted ? Colors.white : Colors.white24,
                      onPressed: _toggleMute,
                      child: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? Colors.black : Colors.white,
                      ),
                    ),
                    // End Call Button
                    FloatingActionButton(
                      heroTag: 'end',
                      backgroundColor: Colors.red,
                      onPressed: () => widget.callService.endCall(),
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
