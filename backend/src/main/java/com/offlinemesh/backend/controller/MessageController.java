package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.SendMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.MessageService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/messages")
@RequiredArgsConstructor
public class MessageController {

    private final MessageService messageService;
    private final UserService userService;

    @PostMapping("/{offlineMeshId}")
    public ResponseEntity<?> sendMessage(@PathVariable String offlineMeshId, @RequestBody SendMessageRequest request) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        try {
            return ResponseEntity.status(HttpStatus.CREATED).body(messageService.sendMessage(currentUser, offlineMeshId, request.getContent()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("message", e.getMessage()));
        }
    }

    @GetMapping("/{offlineMeshId}")
    public ResponseEntity<?> getConversationHistory(@PathVariable String offlineMeshId) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        return ResponseEntity.ok(messageService.getConversationHistory(currentUser, offlineMeshId));
    }
}
