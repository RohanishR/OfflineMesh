package com.offlinemesh.backend.dto;

import com.offlinemesh.backend.entity.enums.MessageType;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LanMessageRequest {
    private UUID messageId;
    private String senderOfflineMeshId;
    private String content;
    private MessageType messageType;
}
