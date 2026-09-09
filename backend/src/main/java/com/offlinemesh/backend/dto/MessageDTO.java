package com.offlinemesh.backend.dto;

import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class MessageDTO {
    private String id;
    private String conversationId;
    private String senderOfflineMeshId;
    private String recipientOfflineMeshId;
    private String content;
    private MessageType messageType;
    private MessageStatus status;
    private TransportType transportType;
    private String fileMetadataReference;
    private String replyToId;
    private String createdAt;
    private String updatedAt;
}
