package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.SendMessageRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.MessageService;
import com.offlinemesh.backend.service.UserService;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

class MessageControllerLiveTest {
    @Test
    void persistedHttpMessageIsPushedToRecipient() {
        var service = mock(MessageService.class);
        var users = mock(UserService.class);
        var broker = mock(SimpMessagingTemplate.class);
        var controller = new MessageController(service, users, broker);
        var user = User.builder().username("sender").offlineMeshId("OM-SENDER").build();
        var request = new SendMessageRequest();
        request.setContent("encrypted-payload");
        var response = MessageResponse.builder().id("message-id").content("encrypted-payload").build();
        when(users.findByUsername("sender")).thenReturn(user);
        when(service.sendMessage(user, "OM-RECIPIENT", "encrypted-payload")).thenReturn(response);
        SecurityContextHolder.getContext().setAuthentication(
            new UsernamePasswordAuthenticationToken("sender", null, java.util.List.of()));
        try {
            assertEquals(201, controller.sendMessage("OM-RECIPIENT", request).getStatusCode().value());
            var order = inOrder(service, broker);
            order.verify(service).sendMessage(user, "OM-RECIPIENT", "encrypted-payload");
            order.verify(broker).convertAndSendToUser("OM-RECIPIENT", "/queue/messages", response);
        } finally {
            SecurityContextHolder.clearContext();
        }
    }
}
