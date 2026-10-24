package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.MessageStatusUpdate;
import com.offlinemesh.backend.dto.SendMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.MessageService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/messages")
@RequiredArgsConstructor
public class MessageController {

    private final MessageService messageService;
    private final UserService userService;
    private final SimpMessagingTemplate messagingTemplate;

    private User getAuthenticatedUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return null;
        }
        String username = authentication.getName();
        return userService.findByUsername(username);
    }

    @GetMapping("/conversations")
    public ResponseEntity<?> getConversations() {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(messageService.getConversations(currentUser));
    }

    @PostMapping("/{offlineMeshId}")
    public ResponseEntity<?> sendMessage(@PathVariable String offlineMeshId, @RequestBody SendMessageRequest request) {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        try {
            var response = messageService.sendMessage(currentUser, offlineMeshId, request.getContent());
            messagingTemplate.convertAndSendToUser(offlineMeshId, "/queue/messages", response);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @GetMapping("/{offlineMeshId}")
    public ResponseEntity<?> getConversationHistory(@PathVariable String offlineMeshId) {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        return ResponseEntity.ok(messageService.getConversationHistory(currentUser, offlineMeshId));
    }

    @PutMapping("/{messageId}")
    public ResponseEntity<?> editMessage(@PathVariable UUID messageId, @RequestBody Map<String, String> body) {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String newContent = body.get("content");
        if (newContent == null || newContent.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Message content cannot be empty"));
        }

        try {
            MessageResponse response = messageService.editMessage(currentUser, messageId, newContent);

            // Notify recipient about the edit via status update
            MessageStatusUpdate statusUpdate = MessageStatusUpdate.builder()
                    .messageId(messageId.toString())
                    .senderOfflineMeshId(currentUser.getOfflineMeshId())
                    .recipientOfflineMeshId(response.getRecipientOfflineMeshId())
                    .status("EDITED")
                    .newContent(newContent)
                    .updatedAt(Instant.now().toString())
                    .build();

            messagingTemplate.convertAndSendToUser(response.getRecipientOfflineMeshId(), "/queue/messages/status", statusUpdate);

            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @DeleteMapping("/{messageId}")
    public ResponseEntity<?> deleteMessageForEveryone(@PathVariable UUID messageId) {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        try {
            MessageResponse response = messageService.deleteMessageForEveryone(currentUser, messageId);

            // Broadcast deletion event to recipient
            MessageStatusUpdate statusUpdate = MessageStatusUpdate.builder()
                    .messageId(messageId.toString())
                    .senderOfflineMeshId(currentUser.getOfflineMeshId())
                    .recipientOfflineMeshId(response.getRecipientOfflineMeshId())
                    .status("DELETED")
                    .updatedAt(Instant.now().toString())
                    .build();

            messagingTemplate.convertAndSendToUser(response.getRecipientOfflineMeshId(), "/queue/messages/status", statusUpdate);

            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @PostMapping("/read/{senderOfflineMeshId}")
    public ResponseEntity<?> markMessagesAsRead(@PathVariable String senderOfflineMeshId) {
        User currentUser = getAuthenticatedUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        int count = messageService.markMessagesAsRead(currentUser, senderOfflineMeshId);

        // Notify the original sender that their messages were read
        MessageStatusUpdate statusUpdate = MessageStatusUpdate.builder()
                .senderOfflineMeshId(senderOfflineMeshId)
                .recipientOfflineMeshId(currentUser.getOfflineMeshId())
                .status("READ")
                .updatedAt(Instant.now().toString())
                .build();

        messagingTemplate.convertAndSendToUser(senderOfflineMeshId, "/queue/messages/status", statusUpdate);

        return ResponseEntity.ok(Map.of("markedCount", count, "status", "READ"));
    }
}
