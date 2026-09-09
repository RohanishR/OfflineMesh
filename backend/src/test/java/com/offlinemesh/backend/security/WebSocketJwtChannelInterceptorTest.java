package com.offlinemesh.backend.security;

import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.UserRepository;
import com.offlinemesh.backend.service.JwtService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageHeaders;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;

import java.util.UUID;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WebSocketJwtChannelInterceptorTest {

    @Mock
    private JwtService jwtService;

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private WebSocketJwtChannelInterceptor interceptor;

    private User user;
    private UUID userId;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        userId = UUID.randomUUID();
        user = User.builder().id(userId).username("testuser").offlineMeshId("OM-TEST").build();
    }

    @Test
    void testPreSend_ConnectWithValidJwt_SetsUser() {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
        accessor.addNativeHeader("Authorization", "Bearer valid-token");
        Message<?> message = MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());

        when(jwtService.validateToken("valid-token")).thenReturn(true);
        when(jwtService.extractUserId("valid-token")).thenReturn(userId.toString());
        when(userRepository.findById(userId)).thenReturn(Optional.of(user));

        Message<?> result = interceptor.preSend(message, null);
        assertNotNull(result);

        StompHeaderAccessor resultAccessor = StompHeaderAccessor.getAccessor(result, StompHeaderAccessor.class);
        assertNotNull(resultAccessor.getUser());
        assertEquals("OM-TEST", resultAccessor.getUser().getName());
    }

    @Test
    void testPreSend_ConnectWithInvalidJwt_ThrowsException() {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
        accessor.addNativeHeader("Authorization", "Bearer invalid-token");
        Message<?> message = MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());

        when(jwtService.validateToken("invalid-token")).thenReturn(false);

        assertThrows(IllegalArgumentException.class, () -> interceptor.preSend(message, null));
    }
}
