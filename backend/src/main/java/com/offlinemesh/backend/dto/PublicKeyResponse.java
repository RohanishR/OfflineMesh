package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PublicKeyResponse {
    private String offlineMeshId;
    private String publicKey;
    private String keyId;
    private String fingerprint;
    private Instant createdAt;
    private Instant updatedAt;
}
