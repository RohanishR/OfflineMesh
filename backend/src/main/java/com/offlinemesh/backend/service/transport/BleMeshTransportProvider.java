package com.offlinemesh.backend.service.transport;

import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.model.TransportCapabilities;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Set;

@Component
public class BleMeshTransportProvider implements TransportProvider {

    @Override
    public TransportType getTransportType() {
        return TransportType.BLE_MESH;
    }

    @Override
    public boolean isAvailable() {
        return false;
    }

    @Override
    public boolean isReachable(com.offlinemesh.backend.entity.User recipient) {
        return false;
    }

    @Override
    public TransportCapabilities getCapabilities() {
        return TransportCapabilities.builder()
                .transportType(getTransportType())
                .available(isAvailable())
                .connected(false)
                .supportedCommunicationTypes(Set.of(MessageType.TEXT))
                .lastChecked(Instant.now())
                .build();
    }

    @Override
    public void connect() {
    }

    @Override
    public void disconnect() {
    }

    @Override
    public boolean sendData(com.offlinemesh.backend.entity.CommunicationRoute route, Object data) {
        return false;
    }

    @Override
    public int getPriority() {
        return 3;
    }
}
