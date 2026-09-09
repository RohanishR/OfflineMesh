package com.offlinemesh.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class PublicUserProfileResponse {
    private String offlineMeshId;
    private String username;
}
