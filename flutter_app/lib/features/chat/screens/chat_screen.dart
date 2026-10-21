import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/models/user.dart';
import '../../../core/models/message.dart';
import '../../../core/transport/transport_type.dart';
import '../../../core/services/call_service.dart';
import '../../call/screens/call_screen.dart';
import '../../../core/security/contact_security_model.dart';

class ChatScreen extends StatefulWidget {
  final UserProfile friend;
  final RoutingService routingService;
  final CallService callService;

  const ChatScreen({
    super.key,
    required this.friend,
    required this.routingService,
    required this.callService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<Message> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSending = false;
  ContactSecurityInfo? _contactSecurity;
  
  StreamSubscription? _incomingSub;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadContactSecurity();
    
    // Subscribe to real-time incoming messages
    _incomingSub = widget.routingService.incomingMessages.listen((message) {
      if (message.senderOfflineMeshId == widget.friend.offlineMeshId ||
          (message.senderOfflineMeshId == widget.routingService.wifiMessagingService.currentUser.offlineMeshId)) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == message.id);
            _messages.add(message);
            _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          });
        }
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _errorMessage = null;
    });

    // 1. Instantly load locally persisted messages for offline capability
    try {
      final localMsgs = await widget.routingService.localStorageService.loadConversation(widget.friend.offlineMeshId);
      if (mounted && localMsgs.isNotEmpty) {
        setState(() {
          _messages = localMsgs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading local messages: $e');
    }

    // 2. Fetch remote conversation history from backend when online and merge
    try {
      final remoteMessages = await widget.routingService.messageService.getConversationHistory(widget.friend.offlineMeshId);
      await widget.routingService.localStorageService.saveMessages(widget.friend.offlineMeshId, remoteMessages);
      final merged = await widget.routingService.localStorageService.loadConversation(widget.friend.offlineMeshId);
      if (mounted) {
        setState(() {
          _messages = merged;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_messages.isEmpty) {
            _errorMessage = 'Offline mode: no local history found ($e)';
          }
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final msg = await widget.routingService.sendMessage(widget.friend.offlineMeshId, text);
      _controller.clear();
      
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == msg.id);
          _messages.add(msg);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _loadContactSecurity() async {
    final encService = widget.routingService.encryptionService;
    if (encService != null) {
      try {
        final secInfo = await encService.getContactSecurityInfo(widget.friend.offlineMeshId);
        if (mounted) {
          setState(() {
            _contactSecurity = secInfo;
          });
        }
      } catch (e) {
        debugPrint('Could not load security info for contact: $e');
      }
    }
  }

  void _showSecurityDialog() {
    final encService = widget.routingService.encryptionService;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isVerified = _contactSecurity?.verificationStatus == VerificationStatus.VERIFIED;
          final isKeyChanged = _contactSecurity?.verificationStatus == VerificationStatus.KEY_CHANGED;
          final fingerprint = _contactSecurity?.fingerprint ?? 'No public key registered yet';

          Color statusColor = Colors.orange;
          String statusText = 'UNVERIFIED';
          IconData statusIcon = Icons.lock_outline;

          if (isVerified) {
            statusColor = Colors.green;
            statusText = 'VERIFIED';
            statusIcon = Icons.verified_user;
          } else if (isKeyChanged) {
            statusColor = Colors.red;
            statusText = 'KEY CHANGED (WARNING)';
            statusIcon = Icons.warning_amber_rounded;
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 8),
                const Text('E2EE Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Messages and files with ${widget.friend.username} are end-to-end encrypted.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isKeyChanged) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Warning: The public key of this contact changed unexpectedly. Verify out-of-band before trusting this contact.',
                      style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Safety Number / Fingerprint:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      fingerprint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Compare this fingerprint out-of-band (e.g. in person or via trusted audio call) to ensure your communication is not intercepted.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              if (encService != null && _contactSecurity != null)
                TextButton(
                  onPressed: () async {
                    final newStatus = isVerified ? VerificationStatus.UNVERIFIED : VerificationStatus.VERIFIED;
                    await encService.setContactVerification(widget.friend.offlineMeshId, newStatus);
                    final updated = await encService.getContactSecurityInfo(widget.friend.offlineMeshId);
                    setDialogState(() {
                      _contactSecurity = updated;
                    });
                    setState(() {
                      _contactSecurity = updated;
                    });
                  },
                  child: Text(
                    isVerified ? 'Mark as Unverified' : 'Mark as Verified',
                    style: TextStyle(color: isVerified ? Colors.grey : Colors.green),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNearby = widget.routingService.isPeerNearby(widget.friend.offlineMeshId);
    final isVerified = _contactSecurity?.verificationStatus == VerificationStatus.VERIFIED;
    final isKeyChanged = _contactSecurity?.verificationStatus == VerificationStatus.KEY_CHANGED;
    
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _showSecurityDialog,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.friend.username),
                  const SizedBox(width: 6),
                  Icon(
                    isVerified
                        ? Icons.verified_user
                        : isKeyChanged
                            ? Icons.warning_amber_rounded
                            : Icons.lock_outline,
                    size: 16,
                    color: isVerified
                        ? Colors.green
                        : isKeyChanged
                            ? Colors.red
                            : Colors.grey.shade700,
                  ),
                ],
              ),
              if (isNearby)
                const Text(
                  'Nearby • Wi-Fi LAN',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                )
              else
                const Text(
                  'End-to-End Encrypted',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isVerified
                  ? Icons.verified_user
                  : isKeyChanged
                      ? Icons.warning_amber_rounded
                      : Icons.lock_outline,
              color: isVerified
                  ? Colors.green
                  : isKeyChanged
                      ? Colors.red
                      : null,
            ),
            tooltip: 'Security & Fingerprint',
            onPressed: _showSecurityDialog,
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              if (!widget.callService.canStartCall(widget.friend.offlineMeshId)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No real-time connection available.')),
                );
                return;
              }
              widget.callService.initiateCall(widget.friend.offlineMeshId, isVideoCall: true);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(callService: widget.callService),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              if (!widget.callService.canStartCall(widget.friend.offlineMeshId)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No real-time connection available.')),
                );
                return;
              }
              widget.callService.initiateCall(widget.friend.offlineMeshId, isVideoCall: false);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(callService: widget.callService),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMessages),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text('Error: $_errorMessage'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.senderOfflineMeshId != widget.friend.offlineMeshId;
                          
                          IconData? statusIcon;
                          Color? statusColor;
                          if (isMe) {
                            if (msg.status == 'sending') {
                              statusIcon = Icons.access_time;
                              statusColor = Colors.grey;
                            } else if (msg.status == 'sent') {
                              statusIcon = Icons.check;
                              statusColor = Colors.green;
                            } else if (msg.status == 'failed') {
                              statusIcon = Icons.error_outline;
                              statusColor = Colors.red;
                            }
                          }

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.blue[100] : Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(msg.content),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (msg.transport == TransportType.WIFI_LAN)
                                        const Icon(Icons.wifi_tethering, size: 12, color: Colors.grey),
                                      if (msg.transport == TransportType.BLUETOOTH)
                                        const Icon(Icons.bluetooth, size: 12, color: Colors.grey),
                                      if (msg.transport == TransportType.BLE)
                                        const Icon(Icons.bluetooth_audio, size: 12, color: Colors.grey),
                                      if (isMe && statusIcon != null) ...[
                                        const SizedBox(width: 4),
                                        Icon(statusIcon, size: 14, color: statusColor),
                                      ]
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const CircularProgressIndicator()
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                        color: Theme.of(context).primaryColor,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
