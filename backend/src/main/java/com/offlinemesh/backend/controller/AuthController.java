package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.RegistrationRequest;
import com.offlinemesh.backend.dto.RegistrationResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final UserService userService;
    private final com.offlinemesh.backend.service.JwtService jwtService;

    @PostMapping("/register")
    public ResponseEntity<RegistrationResponse> register(@Valid @RequestBody RegistrationRequest request) {
        User user = userService.registerUser(request);

        RegistrationResponse response = RegistrationResponse.builder()
                .id(user.getId())
                .username(user.getUsername())
                .email(user.getEmail())
                .offlineMeshId(user.getOfflineMeshId())
                .message("User registered successfully")
                .build();

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/login")
    public ResponseEntity<com.offlinemesh.backend.dto.LoginResponse> login(@Valid @RequestBody com.offlinemesh.backend.dto.LoginRequest request) {
        User user = userService.login(request);
        String token = jwtService.generateToken(user);

        com.offlinemesh.backend.dto.LoginResponse response = com.offlinemesh.backend.dto.LoginResponse.builder()
                .message("Login successful")
                .username(user.getUsername())
                .accessToken(token)
                .tokenType("Bearer")
                .offlineMeshId(user.getOfflineMeshId())
                .build();

        return ResponseEntity.ok(response);
    }

    @org.springframework.web.bind.annotation.GetMapping("/me")
    public ResponseEntity<?> getMe() {
        org.springframework.security.core.Authentication authentication = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        String username = authentication.getName();
        User user = userService.findByUsername(username);
        
        java.util.Map<String, Object> response = new java.util.HashMap<>();
        response.put("id", user.getId());
        response.put("username", user.getUsername());
        response.put("email", user.getEmail());
        response.put("offlineMeshId", user.getOfflineMeshId());
        
        return ResponseEntity.ok(response);
    }

    @org.springframework.web.bind.annotation.PutMapping("/change-password")
    public ResponseEntity<?> changePassword(@org.springframework.web.bind.annotation.RequestBody com.offlinemesh.backend.dto.ChangePasswordRequest request) {
        org.springframework.security.core.Authentication authentication = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal().equals("anonymousUser")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        try {
            userService.changePassword(currentUser, request);
            return ResponseEntity.ok(java.util.Map.of("message", "Password changed successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("message", e.getMessage()));
        }
    }
}
