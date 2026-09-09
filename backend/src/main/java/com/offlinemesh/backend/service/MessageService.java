package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.ConversationRepository;
import com.offlinemesh.backend.repository.FriendshipRepository;
import com.offlinemesh.backend.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class MessageService {

    private final MessageRepository messageRepository;
    private final ConversationRepository conversationRepository;
    private final FriendshipRepository friendshipRepository;
    private final UserService userService;
    private final RoutingService routingService;

    @Transactional
    public MessageResponse sendMessage(User currentUser, String targetOfflineMeshId, String content) {
        User targetUser = userService.getPublicProfile(targetOfflineMeshId);

        if (currentUser.getId().equals(targetUser.getId())) {
            throw new IllegalArgumentException("Cannot send a message to yourself");
        }

        boolean areFriends = friendshipRepository.existsFriendshipBetween(currentUser, targetUser);
        if (!areFriends) {
            throw new com.offlinemesh.backend.exception.NotFriendsException("Cannot send message. You are not friends with this user.");
        }

        Conversation conversation = conversationRepository.findConversationBetween(currentUser, targetUser)
                .orElseGet(() -> {
                    Conversation newConv = Conversation.builder()
                            .user1(currentUser)
                            .user2(targetUser)
                            .build();
                    return conversationRepository.save(newConv);
                });

        java.util.UUID messageId = java.util.UUID.randomUUID();

        com.offlinemesh.backend.dto.LanMessageRequest request = com.offlinemesh.backend.dto.LanMessageRequest.builder()
                .messageId(messageId)
                .senderOfflineMeshId(currentUser.getOfflineMeshId())
                .content(content)
                .messageType(com.offlinemesh.backend.entity.enums.MessageType.TEXT)
                .build();

        com.offlinemesh.backend.entity.CommunicationRoute route = routingService.routeAndSend(currentUser, targetUser, com.offlinemesh.backend.entity.enums.MessageType.TEXT, request);

        Message message = Message.builder()
                .id(messageId)
                .conversation(conversation)
                .sender(currentUser)
                .recipient(targetUser)
                .content(content)
                .messageType(com.offlinemesh.backend.entity.enums.MessageType.TEXT)
                .status(com.offlinemesh.backend.entity.enums.MessageStatus.SENT)
                .transportType(route.getTransportType())
                .build();

        message = messageRepository.save(message);

        return MessageResponse.builder()
                .id(message.getId().toString())
                .senderOfflineMeshId(message.getSender().getOfflineMeshId())
                .content(message.getContent())
                .createdAt(message.getCreatedAt() != null ? message.getCreatedAt().toString() : java.time.Instant.now().toString())
                .build();
    }

    public java.util.Map<String, Object> getConversationHistory(User currentUser, String targetOfflineMeshId) {
        User targetUser = userService.getPublicProfile(targetOfflineMeshId);

        Optional<Conversation> convOpt = conversationRepository.findConversationBetween(currentUser, targetUser);
        
        if (convOpt.isEmpty()) {
            return java.util.Map.of(
                    "conversationId", "",
                    "messages", Collections.emptyList()
            );
        }

        Conversation conversation = convOpt.get();
        List<Message> messages = messageRepository.findByConversationOrderByCreatedAtAsc(conversation);

        List<MessageResponse> responseList = messages.stream().map(m -> MessageResponse.builder()
                .id(m.getId().toString())
                .senderOfflineMeshId(m.getSender().getOfflineMeshId())
                .content(m.getContent())
                .createdAt(m.getCreatedAt() != null ? m.getCreatedAt().toString() : "")
                .build()
        ).collect(Collectors.toList());

        return java.util.Map.of(
                "conversationId", conversation.getId().toString(),
                "messages", responseList
        );
    }

    @Transactional
    public void receiveLanMessage(User currentUser, com.offlinemesh.backend.dto.LanMessageRequest request) {
        if (messageRepository.existsById(request.getMessageId())) {
            // Idempotent: already received this message via another transport
            return;
        }

        User sender = userService.getPublicProfile(request.getSenderOfflineMeshId());
        
        boolean areFriends = friendshipRepository.existsFriendshipBetween(sender, currentUser);
        if (!areFriends) {
            throw new com.offlinemesh.backend.exception.NotFriendsException("Sender is not friends with you.");
        }

        Conversation conversation = conversationRepository.findConversationBetween(sender, currentUser)
                .orElseGet(() -> {
                    Conversation newConv = Conversation.builder()
                            .user1(sender)
                            .user2(currentUser)
                            .build();
                    return conversationRepository.save(newConv);
                });

        Message message = Message.builder()
                .id(request.getMessageId())
                .conversation(conversation)
                .sender(sender)
                .recipient(currentUser)
                .content(request.getContent())
                .messageType(request.getMessageType())
                .status(com.offlinemesh.backend.entity.enums.MessageStatus.DELIVERED)
                .transportType(com.offlinemesh.backend.entity.enums.TransportType.WIFI_LAN) // Received via LAN endpoint
                .build();

        messageRepository.save(message);
    }

    @Transactional
    public MessageResponse sendWebSocketMessage(User currentUser, String targetOfflineMeshId, com.offlinemesh.backend.dto.WebSocketMessageRequest request) {
        if (request.getClientMessageId() != null) {
            Optional<Message> existing = messageRepository.findById(request.getClientMessageId());
            if (existing.isPresent()) {
                Message m = existing.get();
                // Ensure the current user is the actual sender of this existing message
                if (!m.getSender().getId().equals(currentUser.getId())) {
                    throw new com.offlinemesh.backend.exception.UnauthorizedMessagingException("Cannot reuse a client message ID that belongs to another user.");
                }
                return MessageResponse.builder()
                        .id(m.getId().toString())
                        .senderOfflineMeshId(m.getSender().getOfflineMeshId())
                        .content(m.getContent())
                        .createdAt(m.getCreatedAt() != null ? m.getCreatedAt().toString() : java.time.Instant.now().toString())
                        .build();
            }
        }

        User targetUser = userService.getPublicProfile(targetOfflineMeshId);

        boolean areFriends = friendshipRepository.existsFriendshipBetween(currentUser, targetUser);
        if (!areFriends) {
            throw new com.offlinemesh.backend.exception.NotFriendsException("Cannot send message. You are not friends with this user.");
        }

        Conversation conversation = conversationRepository.findConversationBetween(currentUser, targetUser)
                .orElseGet(() -> {
                    Conversation newConv = Conversation.builder()
                            .user1(currentUser)
                            .user2(targetUser)
                            .build();
                    return conversationRepository.save(newConv);
                });

        java.util.UUID messageId = request.getClientMessageId() != null ? request.getClientMessageId() : java.util.UUID.randomUUID();

        Message message = Message.builder()
                .id(messageId)
                .conversation(conversation)
                .sender(currentUser)
                .recipient(targetUser)
                .content(request.getContent())
                .messageType(request.getMessageType() != null ? request.getMessageType() : com.offlinemesh.backend.entity.enums.MessageType.TEXT)
                .status(com.offlinemesh.backend.entity.enums.MessageStatus.SENT)
                .transportType(com.offlinemesh.backend.entity.enums.TransportType.INTERNET)
                .build();

        message = messageRepository.save(message);

        return MessageResponse.builder()
                .id(message.getId().toString())
                .senderOfflineMeshId(message.getSender().getOfflineMeshId())
                .content(message.getContent())
                .createdAt(message.getCreatedAt() != null ? message.getCreatedAt().toString() : java.time.Instant.now().toString())
                .build();
    }
}
