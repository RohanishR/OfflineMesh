package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.PublicUserProfileResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping("/{offlineMeshId}")
    public ResponseEntity<PublicUserProfileResponse> getPublicProfile(@PathVariable String offlineMeshId) {
        // Validate basic format before querying (Optional, but good practice. OM- followed by 8 alphanumeric chars)
        if (offlineMeshId == null || !offlineMeshId.matches("^OM-[A-Z0-9]{8}$")) {
            throw new com.offlinemesh.backend.exception.UserNotFoundException("User not found"); // Fast fail if format is wrong
        }

        User user = userService.getPublicProfile(offlineMeshId);

        PublicUserProfileResponse response = PublicUserProfileResponse.builder()
                .offlineMeshId(user.getOfflineMeshId())
                .username(user.getUsername())
                .build();

        return ResponseEntity.ok(response);
    }

    @org.springframework.web.bind.annotation.GetMapping("/me/profile")
    public ResponseEntity<?> getMyProfile() {
        org.springframework.security.core.Authentication authentication = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(org.springframework.http.HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        java.util.Map<String, Object> response = new java.util.HashMap<>();
        response.put("id", currentUser.getId());
        response.put("username", currentUser.getUsername());
        response.put("email", currentUser.getEmail());
        response.put("offlineMeshId", currentUser.getOfflineMeshId());

        return ResponseEntity.ok(response);
    }

    @org.springframework.web.bind.annotation.PutMapping("/me")
    public ResponseEntity<PublicUserProfileResponse> updateProfile(@org.springframework.web.bind.annotation.RequestBody com.offlinemesh.backend.dto.UpdateProfileRequest request) {
        org.springframework.security.core.Authentication authentication = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(org.springframework.http.HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        User updatedUser = userService.updateProfile(currentUser, request);
        
        PublicUserProfileResponse response = PublicUserProfileResponse.builder()
                .offlineMeshId(updatedUser.getOfflineMeshId())
                .username(updatedUser.getUsername())
                .build();
        
        return ResponseEntity.ok(response);
    }
}
