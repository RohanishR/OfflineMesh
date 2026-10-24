package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.CreateGroupRequest;
import com.offlinemesh.backend.dto.GroupDTO;
import com.offlinemesh.backend.dto.SendMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.GroupService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/groups")
@RequiredArgsConstructor
public class GroupController {

    private final GroupService groupService;
    private final UserService userService;

    private User getAuthenticatedUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || "anonymousUser".equals(auth.getPrincipal())) {
            throw new SecurityException("Unauthorized");
        }
        return userService.findByUsername(auth.getName());
    }

    @PostMapping
    public ResponseEntity<?> createGroup(@RequestBody CreateGroupRequest request) {
        try {
            User currentUser = getAuthenticatedUser();
            GroupDTO group = groupService.createGroup(currentUser, request);
            return ResponseEntity.status(HttpStatus.CREATED).body(group);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @GetMapping
    public ResponseEntity<List<GroupDTO>> getUserGroups() {
        User currentUser = getAuthenticatedUser();
        return ResponseEntity.ok(groupService.getUserGroups(currentUser));
    }

    @GetMapping("/{groupId}")
    public ResponseEntity<?> getGroupDetails(@PathVariable UUID groupId) {
        try {
            User currentUser = getAuthenticatedUser();
            return ResponseEntity.ok(groupService.getGroupDetails(currentUser, groupId));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @PostMapping("/{groupId}/members/{offlineMeshId}")
    public ResponseEntity<?> addMember(@PathVariable UUID groupId, @PathVariable String offlineMeshId) {
        try {
            User currentUser = getAuthenticatedUser();
            return ResponseEntity.ok(groupService.addMember(currentUser, groupId, offlineMeshId));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @DeleteMapping("/{groupId}/members/{offlineMeshId}")
    public ResponseEntity<?> removeMember(@PathVariable UUID groupId, @PathVariable String offlineMeshId) {
        try {
            User currentUser = getAuthenticatedUser();
            return ResponseEntity.ok(groupService.removeMember(currentUser, groupId, offlineMeshId));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @GetMapping("/{groupId}/messages")
    public ResponseEntity<?> getGroupMessages(@PathVariable UUID groupId) {
        try {
            User currentUser = getAuthenticatedUser();
            return ResponseEntity.ok(groupService.getGroupMessages(currentUser, groupId));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }

    @PostMapping("/{groupId}/messages")
    public ResponseEntity<?> sendGroupMessage(@PathVariable UUID groupId, @RequestBody SendMessageRequest request) {
        try {
            User currentUser = getAuthenticatedUser();
            return ResponseEntity.ok(groupService.sendGroupMessage(currentUser, groupId, request));
        } catch (SecurityException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        }
    }
}
