package com.offlinemesh.backend.domain;

import com.offlinemesh.backend.dto.ConversationDTO;
import com.offlinemesh.backend.dto.MessageStatusUpdate;
import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ConversationDomainTest {

    @Test
    void testMessageEditAndDeleteFlags() {
        User alice = User.builder().id(UUID.randomUUID()).username("alice").offlineMeshId("MESH-ALICE").build();
        User bob = User.builder().id(UUID.randomUUID()).username("bob").offlineMeshId("MESH-BOB").build();
        Conversation conv = Conversation.builder().id(UUID.randomUUID()).user1(alice).user2(bob).build();

        Message msg = Message.builder()
                .id(UUID.randomUUID())
                .conversation(conv)
                .sender(alice)
                .recipient(bob)
                .content("Hello Bob")
                .messageType(MessageType.TEXT)
                .status(MessageStatus.SENT)
                .transportType(TransportType.INTERNET)
                .isEdited(false)
                .isDeleted(false)
                .build();

        assertFalse(msg.isEdited());
        assertFalse(msg.isDeleted());

        msg.setContent("Hello Bob (edited)");
        msg.setEdited(true);
        assertTrue(msg.isEdited());

        msg.setContent("This message was deleted");
        msg.setDeleted(true);
        assertTrue(msg.isDeleted());
    }

    @Test
    void testConversationDTOAndStatusUpdate() {
        ConversationDTO dto = ConversationDTO.builder()
                .conversationId("conv-123")
                .otherOfflineMeshId("MESH-BOB")
                .otherUsername("bob")
                .lastMessage("See you tomorrow")
                .lastMessageSenderId("MESH-BOB")
                .lastMessageStatus("DELIVERED")
                .lastMessageType("TEXT")
                .lastMessageTime("2026-10-23T23:00:00Z")
                .unreadCount(3)
                .isLastMessageFromMe(false)
                .isLastMessageEdited(false)
                .isLastMessageDeleted(false)
                .build();

        assertEquals("conv-123", dto.getConversationId());
        assertEquals("MESH-BOB", dto.getOtherOfflineMeshId());
        assertEquals(3, dto.getUnreadCount());
        assertFalse(dto.isLastMessageFromMe());

        MessageStatusUpdate update = MessageStatusUpdate.builder()
                .messageId("msg-999")
                .senderOfflineMeshId("MESH-ALICE")
                .recipientOfflineMeshId("MESH-BOB")
                .status("READ")
                .build();

        assertEquals("READ", update.getStatus());
        assertEquals("msg-999", update.getMessageId());
    }
}
