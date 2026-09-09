package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.LanMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.MessageService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/lan")
@RequiredArgsConstructor
public class LanCommunicationController {

    private final MessageService messageService;

    @PostMapping("/messages")
    public ResponseEntity<Void> receiveLanMessage(
            @AuthenticationPrincipal User currentUser,
            @RequestBody LanMessageRequest request) {

        // Validate that the authenticated user matches the sender ID in the payload.
        // This prevents someone with a valid JWT from impersonating someone else.
        if (!currentUser.getOfflineMeshId().equals(request.getSenderOfflineMeshId())) {
            return ResponseEntity.status(403).build();
        }

        // Forward to the MessageService for idempotent saving
        messageService.receiveLanMessage(currentUser, request);

        return ResponseEntity.ok().build();
    }
}
