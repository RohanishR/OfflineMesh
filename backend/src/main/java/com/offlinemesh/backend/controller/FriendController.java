package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.ConnectRequest;
import com.offlinemesh.backend.dto.ConnectResponse;
import com.offlinemesh.backend.dto.PublicUserProfileResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.FriendshipService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/friends")
@RequiredArgsConstructor
public class FriendController {

    private final FriendshipService friendshipService;
    private final UserService userService;

    @PostMapping("/connect")
    public ResponseEntity<?> connect(@RequestBody ConnectRequest request) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        try {
            User friend = friendshipService.connect(currentUser, request.getOfflineMeshId());
            
            PublicUserProfileResponse friendProfile = PublicUserProfileResponse.builder()
                    .offlineMeshId(friend.getOfflineMeshId())
                    .username(friend.getUsername())
                    .build();
            
            ConnectResponse response = ConnectResponse.builder()
                    .message("Successfully connected")
                    .friend(friendProfile)
                    .build();
            
            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("message", e.getMessage()));
        }
    }

    @org.springframework.web.bind.annotation.GetMapping
    public ResponseEntity<java.util.List<PublicUserProfileResponse>> getFriends() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        java.util.List<User> friends = friendshipService.getFriends(currentUser);
        java.util.List<PublicUserProfileResponse> response = friends.stream()
                .map(friend -> PublicUserProfileResponse.builder()
                        .offlineMeshId(friend.getOfflineMeshId())
                        .username(friend.getUsername())
                        .build())
                .collect(java.util.stream.Collectors.toList());

        return ResponseEntity.ok(response);
    }

    @org.springframework.web.bind.annotation.DeleteMapping("/{offlineMeshId}")
    public ResponseEntity<?> removeFriend(@org.springframework.web.bind.annotation.PathVariable String offlineMeshId) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        try {
            friendshipService.removeFriend(currentUser, offlineMeshId);
            return ResponseEntity.ok(java.util.Map.of("message", "Friendship removed successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("message", e.getMessage()));
        }
    }
}
