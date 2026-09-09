package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.WebSocketMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.security.OfflineMeshPrincipal;
import com.offlinemesh.backend.service.MessageService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.user.SimpUserRegistry;
import org.springframework.messaging.simp.user.SimpUser;
import com.offlinemesh.backend.repository.MessageRepository;
import com.offlinemesh.backend.service.OfflineMessageQueueService;
import com.offlinemesh.backend.entity.Message;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class WebSocketMessageControllerTest {

    @Mock
    private MessageService messageService;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private SimpUserRegistry simpUserRegistry;

    @Mock
    private OfflineMessageQueueService queueService;

    @Mock
    private MessageRepository messageRepository;

    @InjectMocks
    private WebSocketMessageController controller;

    private User sender;
    private OfflineMeshPrincipal principal;
    private WebSocketMessageRequest request;
    private MessageResponse response;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        sender = User.builder()
                .id(UUID.randomUUID())
                .offlineMeshId("OM-SENDER")
                .username("sender")
                .build();

        principal = new OfflineMeshPrincipal(sender);

        request = WebSocketMessageRequest.builder()
                .recipientOfflineMeshId("OM-RECIPIENT")
                .content("Hello STOMP")
                .messageType(MessageType.TEXT)
                .build();

        response = MessageResponse.builder()
                .id(UUID.randomUUID().toString())
                .senderOfflineMeshId("OM-SENDER")
                .content("Hello STOMP")
                .build();
    }

    @Test
    void testPrincipalReturnsOfflineMeshId() {
        assertEquals("OM-SENDER", principal.getName());
    }

    @Test
    void testSendMessage_Success() {
        when(messageService.sendWebSocketMessage(eq(sender), eq("OM-RECIPIENT"), any(WebSocketMessageRequest.class)))
                .thenReturn(response);

        Message mockMessage = new Message();
        when(messageRepository.findById(any())).thenReturn(java.util.Optional.of(mockMessage));

        SimpUser mockSimpUser = mock(SimpUser.class);
        when(simpUserRegistry.getUser("OM-RECIPIENT")).thenReturn(mockSimpUser);

        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth = 
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(principal, null, java.util.Collections.emptyList());

        controller.sendMessage(request, auth);

        // Verify message was processed and saved
        verify(messageService).sendWebSocketMessage(sender, "OM-RECIPIENT", request);

        // Verify message was queued
        verify(queueService).enqueueMessage(mockMessage);

        // Verify message was routed to the exact recipient's queue
        verify(messagingTemplate).convertAndSendToUser(
                "OM-RECIPIENT",
                "/queue/messages",
                response
        );
        
        // Verify it was NOT sent to someone else
        verify(messagingTemplate, never()).convertAndSendToUser(
                eq("OM-SENDER"),
                anyString(),
                any()
        );
    }

    @Test
    void testSendMessage_WrongPrincipalType() {
        java.security.Principal wrongPrincipal = () -> "just-a-string";

        assertThrows(IllegalArgumentException.class, () -> {
            controller.sendMessage(request, wrongPrincipal);
        });

        verify(messageService, never()).sendWebSocketMessage(any(), any(), any());
        verify(messagingTemplate, never()).convertAndSendToUser(anyString(), anyString(), any());
    }
}
