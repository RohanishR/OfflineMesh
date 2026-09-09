package com.offlinemesh.backend.dto;

import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.TransportType;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class DeliveryDTO {
    private String id;
    private String messageId;
    private String senderOfflineMeshId;
    private String recipientOfflineMeshId;
    private TransportType selectedTransport;
    private TransportType actualTransport;
    private MessageStatus status;
    private String sentAt;
    private String deliveredAt;
    private String readAt;
    private int retryCount;
}
