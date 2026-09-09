package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.LanMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.MessageService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class LanCommunicationControllerTest {

    @Mock
    private MessageService messageService;

    @InjectMocks
    private LanCommunicationController controller;

    private User currentUser;
    private LanMessageRequest request;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        currentUser = User.builder().offlineMeshId("OM-SENDER").build();
        request = LanMessageRequest.builder().senderOfflineMeshId("OM-SENDER").content("Hello LAN").build();
    }

    @Test
    void testReceiveLanMessage_Success() {
        ResponseEntity<Void> response = controller.receiveLanMessage(currentUser, request);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(messageService).receiveLanMessage(currentUser, request);
    }

    @Test
    void testReceiveLanMessage_UnauthorizedSpoofing() {
        // Attempt to spoof sender
        request.setSenderOfflineMeshId("OM-FAKE");

        ResponseEntity<Void> response = controller.receiveLanMessage(currentUser, request);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        verify(messageService, never()).receiveLanMessage(any(), any());
    }
}
