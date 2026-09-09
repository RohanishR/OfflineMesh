package com.offlinemesh.backend.service.transport;

import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.model.TransportCapabilities;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Set;

import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.CommunicationRoute;
import com.offlinemesh.backend.service.lan.LanPeerDiscovery;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

@Component
@RequiredArgsConstructor
public class WifiLanTransportProvider implements TransportProvider {

    private final LanPeerDiscovery lanPeerDiscovery;
    private final RestTemplate restTemplate;

    @Override
    public TransportType getTransportType() {
        return TransportType.WIFI_LAN;
    }

    @Override
    public boolean isAvailable() {
        // Assume Wi-Fi radio is turned on and connected to a network
        return true;
    }

    @Override
    public boolean isReachable(User recipient) {
        return lanPeerDiscovery.isPeerReachable(recipient.getOfflineMeshId());
    }

    @Override
    public TransportCapabilities getCapabilities() {
        return TransportCapabilities.builder()
                .transportType(getTransportType())
                .available(isAvailable())
                .connected(false)
                .supportedCommunicationTypes(Set.of(
                        MessageType.TEXT, MessageType.IMAGE, MessageType.VIDEO, 
                        MessageType.AUDIO, MessageType.FILE))
                .lastChecked(Instant.now())
                .build();
    }

    @Override
    public void connect() {
        // Optional physical connection step (like Wi-Fi Direct group formation)
    }

    @Override
    public void disconnect() {
    }

    @Override
    public boolean sendData(CommunicationRoute route, Object data) {
        String peerUrl = lanPeerDiscovery.getPeerAddress(route.getRecipient().getOfflineMeshId());
        if (peerUrl == null) {
            return false;
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            // In a real implementation, we would extract the current user's JWT
            // or use a specific LAN-auth mechanism to populate the Authorization header.
            // For now we just mock sending the data.
            HttpEntity<Object> request = new HttpEntity<>(data, headers);
            
            ResponseEntity<Void> response = restTemplate.postForEntity(peerUrl + "/api/lan/messages", request, Void.class);
            return response.getStatusCode().is2xxSuccessful();
        } catch (Exception e) {
            // Handle connection refused, timeout, etc.
            return false;
        }
    }

    @Override
    public int getPriority() {
        return 1;
    }
}
