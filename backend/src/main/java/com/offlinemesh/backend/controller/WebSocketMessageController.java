package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageAckRequest;
import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.MessageSyncRequest;
import com.offlinemesh.backend.dto.MessageSyncResponse;
import com.offlinemesh.backend.dto.WebSocketMessageRequest;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.repository.MessageRepository;
import com.offlinemesh.backend.security.OfflineMeshPrincipal;
import com.offlinemesh.backend.service.MessageService;
import com.offlinemesh.backend.service.OfflineMessageQueueService;
import com.offlinemesh.backend.service.SynchronizationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageExceptionHandler;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.annotation.SendToUser;
import org.springframework.messaging.simp.user.SimpUserRegistry;
import org.springframework.stereotype.Controller;

import java.security.Principal;
import java.util.Map;
import java.util.UUID;

@Slf4j
@Controller
@RequiredArgsConstructor
public class WebSocketMessageController {

    private final MessageService messageService;
    private final SimpMessagingTemplate messagingTemplate;
    private final SimpUserRegistry simpUserRegistry;
    private final OfflineMessageQueueService queueService;
    private final MessageRepository messageRepository;
    private final SynchronizationService synchronizationService;

    private OfflineMeshPrincipal extractPrincipal(Principal principal) {
        if (principal instanceof org.springframework.security.authentication.UsernamePasswordAuthenticationToken token) {
            if (token.getPrincipal() instanceof OfflineMeshPrincipal) {
                return (OfflineMeshPrincipal) token.getPrincipal();
            }
        } else if (principal instanceof OfflineMeshPrincipal omPrincipal) {
            return omPrincipal;
        }
        return null;
    }

    @MessageMapping("/messages/send")
    public void sendMessage(@Payload WebSocketMessageRequest request, Principal principal) {
        OfflineMeshPrincipal omPrincipal = extractPrincipal(principal);
        if (omPrincipal == null) {
            throw new IllegalArgumentException("User is not authenticated correctly");
        }

        // Persist message using the robust MessageService
        MessageResponse response = messageService.sendWebSocketMessage(
                omPrincipal.getUser(), 
                request.getRecipientOfflineMeshId(), 
                request);

        // Fetch actual message to enqueue
        Message message = messageRepository.findById(UUID.fromString(response.getId()))
                .orElseThrow(() -> new IllegalStateException("Message was not persisted correctly"));

        // Enqueue it as PENDING
        queueService.enqueueMessage(message);

        // Check if recipient is connected and attempt immediate delivery
        boolean isConnected = simpUserRegistry.getUser(request.getRecipientOfflineMeshId()) != null;
        if (isConnected) {
            messagingTemplate.convertAndSendToUser(
                    request.getRecipientOfflineMeshId(),
                    "/queue/messages",
                    response
            );
        }
    }

    @MessageMapping("/messages/ack")
    public void acknowledgeMessage(@Payload MessageAckRequest request, Principal principal) {
        OfflineMeshPrincipal omPrincipal = extractPrincipal(principal);
        if (omPrincipal == null) {
            throw new IllegalArgumentException("User is not authenticated correctly");
        }

        queueService.handleAck(omPrincipal.getUser(), request.getMessageId());
    }

    @MessageMapping("/messages/sync")
    public void syncMessages(@Payload MessageSyncRequest request, Principal principal) {
        OfflineMeshPrincipal omPrincipal = extractPrincipal(principal);
        if (omPrincipal == null) {
            throw new IllegalArgumentException("User is not authenticated correctly");
        }

        MessageSyncResponse response = synchronizationService.syncMessages(omPrincipal.getUser(), request.getCursor(), request.getLimit());

        messagingTemplate.convertAndSendToUser(
                omPrincipal.getName(),
                "/queue/messages/sync",
                response
        );
    }

    @MessageExceptionHandler
    @SendToUser("/queue/errors")
    public Map<String, String> handleException(Exception exception) {
        log.warn("WebSocket message error: {}", exception.getMessage());
        return Map.of("error", exception.getMessage() != null ? exception.getMessage() : "An error occurred");
    }
}
