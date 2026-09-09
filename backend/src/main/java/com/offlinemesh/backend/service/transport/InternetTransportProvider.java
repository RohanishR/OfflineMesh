package com.offlinemesh.backend.service.transport;

import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.model.TransportCapabilities;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Set;

@Component
public class InternetTransportProvider implements TransportProvider {

    @Override
    public TransportType getTransportType() {
        return TransportType.INTERNET;
    }

    @Override
    public boolean isAvailable() {
        return true;
    }

    @Override
    public boolean isReachable(com.offlinemesh.backend.entity.User recipient) {
        return true;
    }

    @Override
    public TransportCapabilities getCapabilities() {
        return TransportCapabilities.builder()
                .transportType(getTransportType())
                .available(isAvailable())
                .connected(true)
                .supportedCommunicationTypes(Set.of(
                        MessageType.TEXT, MessageType.IMAGE, MessageType.VIDEO, 
                        MessageType.AUDIO, MessageType.FILE, MessageType.VOICE_CALL, 
                        MessageType.VIDEO_CALL))
                .lastChecked(Instant.now())
                .build();
    }

    @Override
    public void connect() {
        // No-op for internet fallback
    }

    @Override
    public void disconnect() {
        // No-op for internet fallback
    }

    @Override
    public boolean sendData(com.offlinemesh.backend.entity.CommunicationRoute route, Object data) {
        // Internet persistence handles "sending" natively by writing to DB, so this returns true.
        return true;
    }

    @Override
    public int getPriority() {
        return 4;
    }
}
