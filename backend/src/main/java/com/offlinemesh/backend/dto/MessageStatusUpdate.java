package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MessageStatusUpdate {
    private String messageId;
    private String senderOfflineMeshId;
    private String recipientOfflineMeshId;
    private String status; // READ, EDITED, DELETED, DELIVERED
    private String newContent; // When EDITED
    private String updatedAt;
}
