package com.offlinemesh.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class LoginResponse {
    private String message;
    private String username;
    private String accessToken;
    private String tokenType;
    private String offlineMeshId;
}
