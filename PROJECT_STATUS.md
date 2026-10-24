# OfflineMesh Project Status

**Current Date / Version:** October 2026 | Milestone: WhatsApp-Like Messaging & OfflineMesh Core  
**Branch:** main | **Platform:** Flutter (Android/Multiplatform) + Spring Boot (Java 17 / PostgreSQL)

---

## 1. System Overview & Architecture
OfflineMesh is an offline-first resilient communication and notes platform operating across dynamic connectivity conditions:
- **Local Wi-Fi LAN Direct**: Zero-infrastructure direct peer-to-peer messaging and file transfers via TCP/UDP discovery.
- **Internet / Cloud Relay**: Fallback Spring Boot backend with Stomp WebSocket real-time messaging, asynchronous offline message queue, and E2EE key distribution.
- **Google Keep Notes**: 100% offline note-taking with text, checklists, media attachments, reminders, and pastel styling.
- **E2EE Security**: End-to-end encryption using libsodium-compatible cryptography (SecretBox / Curve25519) with contact safety numbers.

---

## 2. Implementation State by Phase

| Phase | Features | Status | Notes |
|---|---|---|---|
| **Phase 1: Core Chat** | Modern conversation list, live previews, unread badges, pin/archive, read receipts (blue ticks), message editing, delete for everyone, forwarding | **COMPLETED** | Backend endpoints (`/api/messages/conversations`, `PUT`, `DELETE`, `/read/{id}`), Stomp `/queue/messages/status`, Wi-Fi LAN control payloads, Flutter UI with filter chips, action sheets, and real-time sync |
| **Phase 2: Rich Messaging** | Voice note recording/playback, camera/gallery inline sharing, document preview, progress tracking | **COMPLETED** | `VoiceNoteService` (record + audioplayers), `VoiceMessageBubble` with 1x/1.5x/2x speed control, `ImageMessageBubble` with pinch-zoom full-screen viewer, `VideoMessageBubble`, `DocumentMessageBubble`, `AttachmentPickerSheet`, E2EE file encryption & SHA-256 integrity verification |
| **Phase 3: Social & Presence** | Group chats, membership & admin roles, online/offline presence, typing indicators, contact blocking | **COMPLETED** | DB migration `V11__add_group_chats_and_blocking.sql`, `GroupService`, `BlockedUserService`, WebSocket `/topic/presence` & `/app/presence/update`, `GroupChatScreen`, typing/recording broadcast, contact block/unblock UI |
| **Phase 4: Offline Differentiation** | Outbox store-and-forward, Wi-Fi LAN deduplication, multi-transport fallback, sync reconciliation | **COMPLETED** | Persistent deduplication cache with TTL pruning, outbox periodic retry loop (20s) and reconnect triggers, max retries limit with failed status transition, and multi-hop Wi-Fi LAN store-and-forward relay buffer with hop-count loop protection |
| **Phase 5: Calling & Advanced Security** | WebRTC voice/video calls over LAN/Internet, STUN/TURN, key rotation | **COMPLETED** | WebRTC voice/video call buttons in chat with camera flip, mute, speaker, multi-transport routing (Wi-Fi LAN direct vs Internet signaling), STUN/TURN ICE config in settings, safety number verification, and X25519 identity key rotation |

---

## 3. Active Test Verification
- **Flutter Test Suite**: 71/71 tests passing (+8 new tests in `whatsapp_calling_security_test.dart` and +12 in `whatsapp_offline_mesh_test.dart` covering persistent deduplication, outbox retry counter and status transitions, store-and-forward relay buffer, and hop-count decrement).
- **Flutter Static Analysis**: All files in `flutter_app` pass with 0 errors, 0 warnings (`No issues found!`).
- **Backend Test Suite**: 46/46 JUnit tests passing (`BUILD SUCCESS`) on Java 17.
- **Connected Android Test Device**: `moto g64 5G` (`ZD222KYW4R`, Android 15).

---

## 4. Phase 3 Deliverables Summary
1. **Group Conversations (`GroupService` & `GroupChatScreen`)**:
   - **Database Schema**: Added `groups`, `group_members`, `blocked_users` tables and optional `group_id` foreign key on `messages` table via Flyway migration `V11`.
   - **Spring Boot Backend**:
     - `GroupController` (`/api/groups`): `POST /` (create group), `GET /` (list user groups), `GET /{id}` (details), `POST /{id}/members` (add members, admin only), `DELETE /{id}/members/{userOfflineMeshId}` (remove member or leave group), `POST /{id}/messages` (send group message with broadcast to `/topic/group/{id}`).
     - Strict server-side role validation (`GroupRole.ADMIN` vs `GroupRole.MEMBER`).
   - **Flutter Interface (`GroupChatScreen` & `ChatListScreen`)**:
     - New Group creation dialog in compose sheet with name, description, and multi-select friends checklist.
     - Group avatar styling with group icon badge in conversation list.
     - Group chat header showing member count and live members subtitle.
     - Admin badge on group administrator messages and member lists.
     - Add/Remove member modals restricted to admins.
     - "Leave Group" flow with confirmation dialog.
     - Offline caching in `SharedPreferences` for zero-connectivity access.

2. **Real-Time Online, Offline & Typing Presence (`PresenceService`)**:
   - WebSocket presence channel on Spring Boot (`/topic/presence` and `@MessageMapping("/presence/update")`).
   - `UserPresence` data model tracking `isOnline`, `isTyping`, `isRecording`, and `lastSeen`.
   - Dynamic debounced typing indicator broadcast on keystrokes in `_ChatScreenState`.
   - Dynamic recording audio indicator broadcast during voice note recording.
   - WhatsApp-style green subtitle in AppBar ("typing...", "recording audio...", "Online", or transport indicator).

3. **Contact Blocking & Privacy (`BlockedUserService` & `FriendService`)**:
   - Endpoints: `POST /api/friends/block/{id}`, `DELETE /api/friends/block/{id}`, and `GET /api/friends/blocked`.
   - Backend checks prevent blocked users from sending messages or group invitations to the blocker.
   - Flutter UI:
     - 3-dots AppBar menu item "Block Contact" / "Unblock Contact" with alert confirmation.
     - Dynamic state update showing "Blocked" banner in chat.
     - Send bar is disabled when contact is blocked with tap-to-unblock banner.
     - Local caching in `SharedPreferences` (`local_blocked_users`) ensures blocking works offline.

---

## 5. Phase 4 Deliverables Summary (OfflineMesh Differentiation)
1. **Persistent Deduplication Engine (LocalStorageService & RoutingService)**:
   - hasMessageBeenProcessed(messageId) and markMessageProcessed(messageId, expiry) saved to processed_messages.json.
   - Prevents duplicate delivery or re-processing across multi-transport switches (Wi-Fi LAN <-> Internet Relay) and surviving app process restarts.
   - Automatic background TTL pruning of expired records keeping cache bounded.

2. **Autonomous Outbox Retry Engine (RoutingService)**:
   - Continuous 20-second background retry loop for non-empty outboxes.
   - Reconnection hook (messageService.connectionStateStream): instantly flushes queued messages upon STOMP reconnect.
   - Retry counter and error tracking per outbox message item (updateOutboxItem).
   - Circuit breaker & TTL: if an item reaches 10 retry attempts or exceeds 7 days, it automatically transitions to 'failed' status in conversation storage and emits UI notifications for manual tap-to-retry.

3. **Multi-Hop Store-and-Forward Wi-Fi Mesh Routing (WifiMessagingService & RoutingService)**:
   - `relayedPackets` stream and sendRelayPacket on WifiMessagingService.
   - Loop protection: hop-count tracking (hopCount: 1..3, maxHops: 3) and message-ID deduplication immediately drop circular relays.
   - Direct forwarding: if the final recipient is reachable on local Wi-Fi TCP, the intermediate node forwards immediately with incremented hop count.
   - Local buffer: if the recipient is currently offline, packets are saved to `relay_buffer.json` (up to 24h) and flushed when peer discovery registers the target node.


---

## 6. Phase 5 Deliverables Summary (Calling & Advanced Security)
1. **WebRTC Voice & Video Calling (`CallService`, `CallScreen`, `chat_screen.dart`)**:
   - Voice and Video Call buttons integrated into chat AppBar actions.
   - Dual-transport signaling: automatically routes call signaling directly over local Wi-Fi TCP when peers are nearby, falling back to Internet WebSocket signaling.
   - Full in-call controls: mute, speakerphone, camera toggle, camera switch, and call duration timer.
   - Incoming call notification and full-screen ringing UI with Accept and Reject buttons.

2. **Custom STUN / TURN NAT Traversal (`AppConfig`, `settings_screen.dart`)**:
   - Dynamic ICE server resolution in `AppConfig` (`getIceServers` and `setCustomIceServers`).
   - Settings UI allows users behind symmetric NATs or corporate firewalls to configure custom STUN/TURN server URLs and credentials.
   - Immediate reset-to-default option for Google public STUN servers.

3. **Cryptographic Key Rotation & Safety Number Verification (`E2eEncryptionService`, `profile_screen.dart`, `PublicKeyService`)**:
   - `rotateIdentityKeyPair()` generates fresh X25519 identity keys, stores them securely in `FlutterSecureStorage`, recalculates safety number fingerprint, and registers with backend `/api/keys`.
   - Contact security change detection: contact keys changing trigger `KEY_CHANGED` warning banners and out-of-band verification prompts.
   - Profile UI displays current safety number and provides an interactive "Rotate Identity Key Pair" action with confirmation dialog.
