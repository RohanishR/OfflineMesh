package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.CommunicationRoute;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.RouteStatus;
import com.offlinemesh.backend.exception.NoAvailableRouteException;
import com.offlinemesh.backend.service.transport.TransportProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class RoutingService {

    private final TransportAvailabilityService availabilityService;

    /**
     * Attempts to route and send data, falling back to lower-priority transports if transmission fails.
     */
    public CommunicationRoute routeAndSend(User sender, User recipient, MessageType messageType, Object data) {
        if (sender == null || recipient == null) {
            throw new IllegalArgumentException("Sender and recipient must not be null");
        }
        if (messageType == null) {
            throw new IllegalArgumentException("MessageType must not be null");
        }

        java.util.List<TransportProvider> eligibleTransports = availabilityService.getAvailableTransports().stream()
                .filter(transport -> transport.getCapabilities().getSupportedCommunicationTypes().contains(messageType))
                .filter(transport -> transport.isReachable(recipient))
                .sorted(Comparator.comparingInt(TransportProvider::getPriority))
                .toList();

        if (eligibleTransports.isEmpty()) {
            throw new NoAvailableRouteException("No communication transport available to reach the recipient for the requested communication type.");
        }

        for (TransportProvider transport : eligibleTransports) {
            try {
                transport.connect();
                CommunicationRoute route = CommunicationRoute.builder()
                        .sender(sender)
                        .recipient(recipient)
                        .transportType(transport.getTransportType())
                        .status(RouteStatus.CONNECTED)
                        .priority(transport.getPriority())
                        .build();

                boolean success = transport.sendData(route, data);
                if (success) {
                    return route;
                }
            } catch (Exception e) {
                // Log and continue to next transport
            }
        }

        throw new NoAvailableRouteException("All eligible transports failed to deliver the data.");
    }
}
