package com.offlinemesh.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class ConnectResponse {
    private String message;
    private PublicUserProfileResponse friend;
}
