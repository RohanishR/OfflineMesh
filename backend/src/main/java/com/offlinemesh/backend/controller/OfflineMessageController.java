package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.entity.OfflineMessageQueue;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.OfflineMessageQueueService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.Principal;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/messages")
@RequiredArgsConstructor
public class OfflineMessageController {

    private final OfflineMessageQueueService queueService;
    private final UserService userService;

    @GetMapping("/pending")
    public ResponseEntity<List<MessageResponse>> getPendingMessages(Principal principal) {
        if (principal == null) {
            return ResponseEntity.status(401).build();
        }

        // Identify the user making the request
        // JwtAuthenticationFilter puts username into Principal
        User currentUser = userService.findByUsername(principal.getName());

        List<OfflineMessageQueue> pendingQueue = queueService.getPendingMessages(currentUser);

        List<MessageResponse> responseList = pendingQueue.stream()
                .map(entry -> MessageResponse.builder()
                        .id(entry.getMessage().getId().toString())
                        .senderOfflineMeshId(entry.getMessage().getSender().getOfflineMeshId())
                        .content(entry.getMessage().getContent())
                        .createdAt(entry.getMessage().getCreatedAt().toString())
                        .build())
                .collect(Collectors.toList());

        return ResponseEntity.ok(responseList);
    }
}
