package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.OfflineMessageQueue;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.repository.MessageRepository;
import com.offlinemesh.backend.repository.OfflineMessageQueueRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class OfflineMessageQueueServiceTest {

    @Mock
    private OfflineMessageQueueRepository queueRepository;

    @Mock
    private MessageRepository messageRepository;

    @InjectMocks
    private OfflineMessageQueueService queueService;

    private User sender;
    private User recipient;
    private Message message;
    private OfflineMessageQueue queueEntry;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        ReflectionTestUtils.setField(queueService, "maxRetries", 5);
        ReflectionTestUtils.setField(queueService, "retryDelayMs", 5000L);

        sender = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-SENDER").build();
        recipient = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-RECIPIENT").build();

        Conversation conv = Conversation.builder().id(UUID.randomUUID()).user1(sender).user2(recipient).build();

        message = Message.builder()
                .id(UUID.randomUUID())
                .conversation(conv)
                .sender(sender)
                .recipient(recipient)
                .content("Hello")
                .messageType(MessageType.TEXT)
                .status(MessageStatus.SENT)
                .transportType(TransportType.INTERNET)
                .build();

        queueEntry = OfflineMessageQueue.builder()
                .id(UUID.randomUUID())
                .message(message)
                .recipient(recipient)
                .status(MessageStatus.PENDING)
                .attemptCount(0)
                .build();
    }

    @Test
    void testEnqueueMessage_Success() {
        when(queueRepository.findByMessageAndRecipient(message, recipient)).thenReturn(Optional.empty());

        queueService.enqueueMessage(message);

        assertEquals(MessageStatus.PENDING, message.getStatus());
        verify(messageRepository).save(message);
        verify(queueRepository).save(any(OfflineMessageQueue.class));
    }

    @Test
    void testEnqueueMessage_AlreadyDelivered_DoesNothing() {
        message.setStatus(MessageStatus.DELIVERED);

        queueService.enqueueMessage(message);

        verify(messageRepository, never()).save(any());
        verify(queueRepository, never()).save(any());
    }

    @Test
    void testHandleAck_Success() {
        when(messageRepository.findById(message.getId())).thenReturn(Optional.of(message));
        when(queueRepository.findByMessageAndRecipient(message, recipient)).thenReturn(Optional.of(queueEntry));

        queueService.handleAck(recipient, message.getId());

        assertEquals(MessageStatus.DELIVERED, message.getStatus());
        verify(messageRepository).save(message);

        assertEquals(MessageStatus.DELIVERED, queueEntry.getStatus());
        assertNotNull(queueEntry.getDeliveredAt());
        verify(queueRepository).save(queueEntry);
    }

    @Test
    void testHandleAck_WrongRecipient_ThrowsException() {
        when(messageRepository.findById(message.getId())).thenReturn(Optional.of(message));

        User wrongUser = User.builder().id(UUID.randomUUID()).build();

        assertThrows(IllegalArgumentException.class, () -> queueService.handleAck(wrongUser, message.getId()));
    }

    @Test
    void testRecordDeliveryAttempt_IncrementsCount() {
        queueService.recordDeliveryAttempt(queueEntry);

        assertEquals(1, queueEntry.getAttemptCount());
        assertNotNull(queueEntry.getNextAttemptAt());
        verify(queueRepository).save(queueEntry);
    }

    @Test
    void testRecordDeliveryAttempt_MaxRetriesReached() {
        queueEntry.setAttemptCount(5);

        queueService.recordDeliveryAttempt(queueEntry);

        assertEquals(MessageStatus.FAILED, queueEntry.getStatus());
        assertEquals(MessageStatus.FAILED, message.getStatus());
        verify(messageRepository).save(message);
        verify(queueRepository).save(queueEntry);
    }
}
