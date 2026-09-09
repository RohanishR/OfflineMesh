package com.offlinemesh.backend.config;

import com.offlinemesh.backend.security.WebSocketJwtChannelInterceptor;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final WebSocketJwtChannelInterceptor jwtChannelInterceptor;

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        // Enable a simple memory-based message broker to carry the messages back to the client on destinations prefixed with "/topic" and "/queue".
        config.enableSimpleBroker("/topic", "/queue");
        // Designate the "/app" prefix for messages that are bound for methods annotated with @MessageMapping.
        config.setApplicationDestinationPrefixes("/app");
        // Prefix used to identify user destinations. Clients subscribe to /user/queue/messages.
        config.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // The endpoint that clients will use to connect to our WebSocket server
        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns("*"); // Allow all origins for development
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        // Register the interceptor that will validate the JWT on CONNECT and set the Principal
        registration.interceptors(jwtChannelInterceptor);
    }
}
