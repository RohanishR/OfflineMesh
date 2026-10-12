package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.PublicKeyRegistrationRequest;
import com.offlinemesh.backend.dto.PublicKeyResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.UserPublicKey;
import com.offlinemesh.backend.exception.UserNotFoundException;
import com.offlinemesh.backend.repository.UserPublicKeyRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PublicKeyServiceTest {

    @Mock
    private UserPublicKeyRepository userPublicKeyRepository;

    @InjectMocks
    private PublicKeyService publicKeyService;

    private User testUser;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        testUser = User.builder()
                .id(UUID.randomUUID())
                .username("alice")
                .email("alice@test.com")
                .offlineMeshId("OM-ALICE001")
                .build();
    }

    @Test
    void registerPublicKey_Success() {
        PublicKeyRegistrationRequest request = PublicKeyRegistrationRequest.builder()
                .publicKey("MCowBQYDK2VuAyEAtestPublicKeyBase641234567890==")
                .keyId("key-v1")
                .fingerprint("SHA256:abcd1234ef5678")
                .build();

        when(userPublicKeyRepository.findByOfflineMeshId("OM-ALICE001")).thenReturn(Optional.empty());
        when(userPublicKeyRepository.save(any(UserPublicKey.class))).thenAnswer(inv -> {
            UserPublicKey k = inv.getArgument(0);
            k.setId(UUID.randomUUID());
            k.setCreatedAt(Instant.now());
            return k;
        });

        PublicKeyResponse response = publicKeyService.registerPublicKey(testUser, request);

        assertNotNull(response);
        assertEquals("OM-ALICE001", response.getOfflineMeshId());
        assertEquals("MCowBQYDK2VuAyEAtestPublicKeyBase641234567890==", response.getPublicKey());
        assertEquals("key-v1", response.getKeyId());
        assertEquals("SHA256:abcd1234ef5678", response.getFingerprint());
        verify(userPublicKeyRepository).save(any(UserPublicKey.class));
    }

    @Test
    void registerPublicKey_RotateKey_Success() {
        UserPublicKey existing = UserPublicKey.builder()
                .id(UUID.randomUUID())
                .user(testUser)
                .offlineMeshId("OM-ALICE001")
                .publicKey("OLD_KEY")
                .keyId("v0")
                .fingerprint("OLD_FINGERPRINT")
                .build();

        when(userPublicKeyRepository.findByOfflineMeshId("OM-ALICE001")).thenReturn(Optional.of(existing));
        when(userPublicKeyRepository.save(any(UserPublicKey.class))).thenAnswer(inv -> inv.getArgument(0));

        PublicKeyRegistrationRequest request = PublicKeyRegistrationRequest.builder()
                .publicKey("NEW_KEY")
                .keyId("v1")
                .fingerprint("NEW_FINGERPRINT")
                .build();

        PublicKeyResponse response = publicKeyService.registerPublicKey(testUser, request);

        assertEquals("NEW_KEY", response.getPublicKey());
        assertEquals("v1", response.getKeyId());
        assertEquals("NEW_FINGERPRINT", response.getFingerprint());
    }

    @Test
    void getPublicKey_Success() {
        UserPublicKey existing = UserPublicKey.builder()
                .id(UUID.randomUUID())
                .user(testUser)
                .offlineMeshId("OM-ALICE001")
                .publicKey("KEY123")
                .keyId("v1")
                .fingerprint("FP123")
                .createdAt(Instant.now())
                .build();

        when(userPublicKeyRepository.findByOfflineMeshId("OM-ALICE001")).thenReturn(Optional.of(existing));

        PublicKeyResponse response = publicKeyService.getPublicKey("OM-ALICE001");

        assertNotNull(response);
        assertEquals("OM-ALICE001", response.getOfflineMeshId());
        assertEquals("KEY123", response.getPublicKey());
    }

    @Test
    void getPublicKey_NotFound_ThrowsException() {
        when(userPublicKeyRepository.findByOfflineMeshId("OM-UNKNOWN")).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class, () -> publicKeyService.getPublicKey("OM-UNKNOWN"));
    }
}
