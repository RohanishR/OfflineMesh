package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageSyncRequest;
import com.offlinemesh.backend.dto.MessageSyncResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.SynchronizationService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.security.Principal;

@RestController
@RequestMapping("/api/messages")
@RequiredArgsConstructor
public class MessageSyncController {

    private final SynchronizationService synchronizationService;
    private final UserService userService;

    @GetMapping("/sync")
    public ResponseEntity<MessageSyncResponse> syncMessages(
            @RequestParam(required = false) String cursor,
            @RequestParam(required = false, defaultValue = "50") Integer limit,
            Principal principal) {
        
        if (principal == null) {
            return ResponseEntity.status(401).build();
        }

        User currentUser = userService.findByUsername(principal.getName());

        MessageSyncResponse response = synchronizationService.syncMessages(currentUser, cursor, limit);

        return ResponseEntity.ok(response);
    }
}
