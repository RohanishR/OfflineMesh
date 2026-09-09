package com.offlinemesh.backend.security;

import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.UserRepository;
import com.offlinemesh.backend.service.JwtService;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.stereotype.Component;

import java.util.Collections;

@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketJwtChannelInterceptor implements ChannelInterceptor {

    private final JwtService jwtService;
    private final UserRepository userRepository;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);

        if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
            String authHeader = accessor.getFirstNativeHeader("Authorization");
            if (authHeader != null && authHeader.startsWith("Bearer ")) {
                String jwt = authHeader.substring(7);
                try {
                    if (jwtService.validateToken(jwt)) {
                        String userIdStr = jwtService.extractUserId(jwt);
                        UUID userId = UUID.fromString(userIdStr);
                        
                        // We must load the user to get the offlineMeshId
                        User user = userRepository.findById(userId)
                                .orElseThrow(() -> new IllegalArgumentException("User not found"));

                        OfflineMeshPrincipal principal = new OfflineMeshPrincipal(user);
                        
                        UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                                principal, null, Collections.emptyList()
                        );
                        
                        // Set the Principal on a mutable accessor.
                        StompHeaderAccessor mutableAccessor = StompHeaderAccessor.wrap(message);
                        mutableAccessor.setUser(authentication);
                        return org.springframework.messaging.support.MessageBuilder.createMessage(message.getPayload(), mutableAccessor.getMessageHeaders());
                    } else {
                        log.warn("Invalid JWT presented during STOMP connection.");
                        throw new IllegalArgumentException("Invalid JWT token");
                    }
                } catch (Exception e) {
                    log.warn("Authentication failed during STOMP connection: {}", e.getMessage());
                    throw new IllegalArgumentException("Authentication failed");
                }
            } else {
                throw new IllegalArgumentException("Missing or invalid Authorization header");
            }
        }
        return message;
    }
}
