package com.offlinemesh.backend.dto;

import lombok.Builder;
import lombok.Data;

import java.util.UUID;

@Data
@Builder
public class RegistrationResponse {
    private UUID id;
    private String username;
    private String email;
    private String offlineMeshId;
    private String message;
}
