package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.entity.OfflineMessageQueue;
import com.offlinemesh.backend.security.OfflineMeshPrincipal;
import com.offlinemesh.backend.service.OfflineMessageQueueService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.messaging.SessionSubscribeEvent;

import java.security.Principal;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketEventListener {

    private final OfflineMessageQueueService queueService;
    private final SimpMessagingTemplate messagingTemplate;

    @EventListener
    public void handleSessionSubscribeEvent(SessionSubscribeEvent event) {
        StompHeaderAccessor accessor = StompHeaderAccessor.wrap(event.getMessage());
        String destination = accessor.getDestination();

        // When a user subscribes to their personal message queue, flush pending messages
        if (destination != null && destination.endsWith("/queue/messages")) {
            Principal principal = accessor.getUser();
            OfflineMeshPrincipal omPrincipal = extractPrincipal(principal);

            if (omPrincipal != null) {
                log.info("User {} subscribed to messages queue. Flushing pending messages.", omPrincipal.getName());
                
                List<OfflineMessageQueue> pendingMessages = queueService.getPendingMessages(omPrincipal.getUser());
                
                for (OfflineMessageQueue queueEntry : pendingMessages) {
                    MessageResponse response = MessageResponse.builder()
                            .id(queueEntry.getMessage().getId().toString())
                            .senderOfflineMeshId(queueEntry.getMessage().getSender().getOfflineMeshId())
                            .content(queueEntry.getMessage().getContent())
                            .createdAt(queueEntry.getMessage().getCreatedAt().toString())
                            .build();

                    messagingTemplate.convertAndSendToUser(
                            omPrincipal.getName(),
                            "/queue/messages",
                            response
                    );
                    
                    queueService.recordDeliveryAttempt(queueEntry);
                }
            }
        }
    }

    private OfflineMeshPrincipal extractPrincipal(Principal principal) {
        if (principal instanceof UsernamePasswordAuthenticationToken token) {
            if (token.getPrincipal() instanceof OfflineMeshPrincipal) {
                return (OfflineMeshPrincipal) token.getPrincipal();
            }
        } else if (principal instanceof OfflineMeshPrincipal omPrincipal) {
            return omPrincipal;
        }
        return null;
    }
}
