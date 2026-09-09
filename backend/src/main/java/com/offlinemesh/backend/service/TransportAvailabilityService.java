package com.offlinemesh.backend.service;

import com.offlinemesh.backend.model.TransportCapabilities;
import com.offlinemesh.backend.service.transport.TransportProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class TransportAvailabilityService {

    private final List<TransportProvider> providers;

    /**
     * Retrieves the capabilities of all registered transports.
     */
    public List<TransportCapabilities> getAllCapabilities() {
        return providers.stream()
                .map(TransportProvider::getCapabilities)
                .collect(Collectors.toList());
    }

    /**
     * Retrieves all transports that are currently available.
     */
    public List<TransportProvider> getAvailableTransports() {
        return providers.stream()
                .filter(TransportProvider::isAvailable)
                .collect(Collectors.toList());
    }
}
