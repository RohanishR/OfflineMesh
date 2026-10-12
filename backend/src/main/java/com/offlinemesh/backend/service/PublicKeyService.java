package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.PublicKeyRegistrationRequest;
import com.offlinemesh.backend.dto.PublicKeyResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.UserPublicKey;
import com.offlinemesh.backend.exception.UserNotFoundException;
import com.offlinemesh.backend.repository.UserPublicKeyRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class PublicKeyService {

    private final UserPublicKeyRepository userPublicKeyRepository;

    @Transactional
    public PublicKeyResponse registerPublicKey(User currentUser, PublicKeyRegistrationRequest request) {
        if (request.getPublicKey() == null || request.getPublicKey().isBlank()) {
            throw new IllegalArgumentException("Public key cannot be empty");
        }
        if (request.getKeyId() == null || request.getKeyId().isBlank()) {
            throw new IllegalArgumentException("Key ID cannot be empty");
        }
        if (request.getFingerprint() == null || request.getFingerprint().isBlank()) {
            throw new IllegalArgumentException("Fingerprint cannot be empty");
        }

        Optional<UserPublicKey> existingOpt = userPublicKeyRepository.findByOfflineMeshId(currentUser.getOfflineMeshId());
        UserPublicKey userPublicKey;

        if (existingOpt.isPresent()) {
            userPublicKey = existingOpt.get();
            if (!userPublicKey.getPublicKey().equals(request.getPublicKey())) {
                log.info("Detected key rotation for user {} (OfflineMesh ID: {})", currentUser.getUsername(), currentUser.getOfflineMeshId());
                userPublicKey.setPublicKey(request.getPublicKey());
                userPublicKey.setKeyId(request.getKeyId());
                userPublicKey.setFingerprint(request.getFingerprint());
                userPublicKey.setUpdatedAt(Instant.now());
            }
        } else {
            userPublicKey = UserPublicKey.builder()
                    .user(currentUser)
                    .offlineMeshId(currentUser.getOfflineMeshId())
                    .publicKey(request.getPublicKey())
                    .keyId(request.getKeyId())
                    .fingerprint(request.getFingerprint())
                    .build();
            log.info("Registered new identity public key for user {} (OfflineMesh ID: {})", currentUser.getUsername(), currentUser.getOfflineMeshId());
        }

        userPublicKey = userPublicKeyRepository.save(userPublicKey);
        return mapToResponse(userPublicKey);
    }

    @Transactional(readOnly = true)
    public PublicKeyResponse getPublicKey(String offlineMeshId) {
        UserPublicKey userPublicKey = userPublicKeyRepository.findByOfflineMeshId(offlineMeshId)
                .orElseThrow(() -> new UserNotFoundException("No public key found for OfflineMesh ID: " + offlineMeshId));

        return mapToResponse(userPublicKey);
    }

    private PublicKeyResponse mapToResponse(UserPublicKey userPublicKey) {
        return PublicKeyResponse.builder()
                .offlineMeshId(userPublicKey.getOfflineMeshId())
                .publicKey(userPublicKey.getPublicKey())
                .keyId(userPublicKey.getKeyId())
                .fingerprint(userPublicKey.getFingerprint())
                .createdAt(userPublicKey.getCreatedAt())
                .updatedAt(userPublicKey.getUpdatedAt())
                .build();
    }
}
