package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.MessageSyncResponse;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.MessageRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

class SynchronizationServiceTest {

    @Mock
    private MessageRepository messageRepository;

    @InjectMocks
    private SynchronizationService synchronizationService;

    private User recipient;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        recipient = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-RECIPIENT").build();
    }

    @Test
    void testSyncMessages_FirstTimeSync() {
        List<Message> mockMessages = new ArrayList<>();
        Instant now = Instant.now();
        // Assume repo returns newest first for no cursor
        mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg 3").createdAt(now).build());
        mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg 2").createdAt(now.minusSeconds(1)).build());
        mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg 1").createdAt(now.minusSeconds(2)).build());

        when(messageRepository.findByRecipientOrderByCreatedAtDesc(eq(recipient), any(Pageable.class)))
                .thenReturn(mockMessages);

        MessageSyncResponse response = synchronizationService.syncMessages(recipient, null, 10);

        // Service should reverse them
        assertEquals(3, response.getMessages().size());
        assertEquals("Msg 1", response.getMessages().get(0).getContent());
        assertEquals("Msg 3", response.getMessages().get(2).getContent());
        assertFalse(response.isHasMore());
        assertEquals(now.toString(), response.getNextCursor());
    }

    @Test
    void testSyncMessages_WithCursor() {
        List<Message> mockMessages = new ArrayList<>();
        Instant cursor = Instant.now().minusSeconds(10);
        Instant now = Instant.now();
        
        mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg 1").createdAt(now.minusSeconds(2)).build());
        mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg 2").createdAt(now.minusSeconds(1)).build());

        when(messageRepository.findByRecipientAndCreatedAtGreaterThanOrderByCreatedAtAsc(eq(recipient), eq(cursor), any(Pageable.class)))
                .thenReturn(mockMessages);

        MessageSyncResponse response = synchronizationService.syncMessages(recipient, cursor.toString(), 10);

        assertEquals(2, response.getMessages().size());
        assertEquals("Msg 1", response.getMessages().get(0).getContent());
        assertEquals("Msg 2", response.getMessages().get(1).getContent());
        assertFalse(response.isHasMore());
        assertEquals(now.minusSeconds(1).toString(), response.getNextCursor());
    }

    @Test
    void testSyncMessages_HasMore() {
        List<Message> mockMessages = new ArrayList<>();
        Instant cursor = Instant.now().minusSeconds(10);
        
        for (int i = 0; i < 4; i++) {
            mockMessages.add(Message.builder().id(UUID.randomUUID()).sender(recipient).content("Msg " + i).createdAt(Instant.now()).build());
        }

        // Limit is 3, query fetches 4
        when(messageRepository.findByRecipientAndCreatedAtGreaterThanOrderByCreatedAtAsc(eq(recipient), eq(cursor), any(Pageable.class)))
                .thenReturn(mockMessages);

        MessageSyncResponse response = synchronizationService.syncMessages(recipient, cursor.toString(), 3);

        assertEquals(3, response.getMessages().size());
        assertTrue(response.isHasMore());
        assertEquals("Msg 0", response.getMessages().get(0).getContent());
        assertEquals("Msg 2", response.getMessages().get(2).getContent());
    }
}
