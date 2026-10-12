package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.PublicKeyRegistrationRequest;
import com.offlinemesh.backend.dto.PublicKeyResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.PublicKeyService;
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
@RequestMapping("/api/keys")
@RequiredArgsConstructor
public class PublicKeyController {

    private final PublicKeyService publicKeyService;
    private final UserService userService;

    @PostMapping
    public ResponseEntity<PublicKeyResponse> registerPublicKey(@RequestBody PublicKeyRegistrationRequest request) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || "anonymousUser".equals(authentication.getPrincipal())) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String username = authentication.getName();
        User currentUser = userService.findByUsername(username);

        PublicKeyResponse response = publicKeyService.registerPublicKey(currentUser, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/{offlineMeshId}")
    public ResponseEntity<PublicKeyResponse> getPublicKey(@PathVariable String offlineMeshId) {
        PublicKeyResponse response = publicKeyService.getPublicKey(offlineMeshId);
        return ResponseEntity.ok(response);
    }
}
