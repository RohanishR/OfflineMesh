package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.WebRtcSignalingMessage;
import com.offlinemesh.backend.dto.WebRtcSignalingMessageType;
import com.offlinemesh.backend.security.OfflineMeshPrincipal;
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
import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

@Slf4j
@Controller
@RequiredArgsConstructor
public class WebRtcSignalingController {

    private final SimpMessagingTemplate messagingTemplate;
    private final SimpUserRegistry simpUserRegistry;

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

    @MessageMapping("/webrtc/signal")
    public void handleSignalingMessage(@Payload WebRtcSignalingMessage message, Principal principal) {
        OfflineMeshPrincipal omPrincipal = extractPrincipal(principal);
        if (omPrincipal == null) {
            throw new IllegalArgumentException("User is not authenticated correctly");
        }

        // Validate sender matches the authenticated user to prevent spoofing
        if (!omPrincipal.getUser().getOfflineMeshId().equals(message.getSenderOfflineMeshId())) {
            log.warn("Spoofing attempt detected. Authenticated user {} tried to send message as {}",
                    omPrincipal.getUser().getOfflineMeshId(), message.getSenderOfflineMeshId());
            throw new IllegalArgumentException("Sender ID does not match authenticated user");
        }

        // Ensure mandatory fields are present
        if (message.getSessionId() == null || message.getRecipientOfflineMeshId() == null || message.getType() == null) {
            throw new IllegalArgumentException("Missing mandatory signaling fields");
        }
        
        // Stamp server time if absent
        if (message.getTimestamp() == null) {
            message.setTimestamp(LocalDateTime.now());
        }

        String recipientId = message.getRecipientOfflineMeshId();
        boolean isConnected = simpUserRegistry.getUser(recipientId) != null;

        if (isConnected) {
            log.debug("Routing signaling message type {} from {} to {}", 
                    message.getType(), message.getSenderOfflineMeshId(), recipientId);
            messagingTemplate.convertAndSendToUser(
                    recipientId,
                    "/queue/webrtc",
                    message
            );
        } else {
            log.debug("Recipient {} is not connected. Signaling message dropped.", recipientId);
            
            // If the caller is offering, let them know immediately it failed
            if (message.getType() == WebRtcSignalingMessageType.CALL_OFFER) {
                WebRtcSignalingMessage failureResponse = WebRtcSignalingMessage.builder()
                        .id(UUID.randomUUID().toString())
                        .sessionId(message.getSessionId())
                        .senderOfflineMeshId(recipientId) // Send back as if the recipient rejected
                        .recipientOfflineMeshId(message.getSenderOfflineMeshId())
                        .type(WebRtcSignalingMessageType.CALL_FAILED)
                        .timestamp(LocalDateTime.now())
                        .build();
                        
                messagingTemplate.convertAndSendToUser(
                        message.getSenderOfflineMeshId(),
                        "/queue/webrtc",
                        failureResponse
                );
            }
        }
    }

    @MessageExceptionHandler
    @SendToUser("/queue/errors")
    public Map<String, String> handleException(Exception e) {
        log.error("Error handling WebRTC signaling message: {}", e.getMessage());
        return Map.of("error", e.getMessage());
    }
}
