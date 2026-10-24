package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ConversationDTO {
    private String conversationId;
    private String otherOfflineMeshId;
    private String otherUsername;
    private String lastMessage;
    private String lastMessageSenderId;
    private String lastMessageStatus;
    private String lastMessageType;
    private String lastMessageTime;
    private long unreadCount;
    private boolean isLastMessageFromMe;
    private boolean isLastMessageEdited;
    private boolean isLastMessageDeleted;
}
