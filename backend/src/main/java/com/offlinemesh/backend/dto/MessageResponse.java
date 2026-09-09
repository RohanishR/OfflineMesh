package com.offlinemesh.backend.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class MessageResponse {
    private String id;
    private String senderOfflineMeshId;
    private String content;
    private String createdAt;
}
