package com.offlinemesh.backend.dto;

import lombok.Data;

@Data
public class UpdateProfileRequest {
    private String username;
    private String email;
}
