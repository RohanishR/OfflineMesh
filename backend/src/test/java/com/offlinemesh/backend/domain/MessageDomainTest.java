package com.offlinemesh.backend.domain;

import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

class MessageDomainTest {

    @Test
    void testMessageBuilderAndEnums() {
        User sender = User.builder().id(UUID.randomUUID()).username("sender").build();
        User recipient = User.builder().id(UUID.randomUUID()).username("recipient").build();
        Conversation conversation = Conversation.builder().id(UUID.randomUUID()).user1(sender).user2(recipient).build();
        
        UUID messageId = UUID.randomUUID();
        Message message = Message.builder()
                .id(messageId)
                .conversation(conversation)
                .sender(sender)
                .recipient(recipient)
                .content("Hello")
                .messageType(MessageType.TEXT)
                .status(MessageStatus.PENDING)
                .transportType(TransportType.WIFI_LAN)
                .build();

        assertNotNull(message.getId());
        assertEquals(messageId, message.getId());
        assertEquals(MessageType.TEXT, message.getMessageType());
        assertEquals(MessageStatus.PENDING, message.getStatus());
        assertEquals(TransportType.WIFI_LAN, message.getTransportType());
        assertEquals(sender, message.getSender());
        assertEquals(recipient, message.getRecipient());
        assertEquals(conversation, message.getConversation());
        assertNull(message.getFileMetadataReference());
    }
}
