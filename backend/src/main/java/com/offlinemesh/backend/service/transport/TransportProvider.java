package com.offlinemesh.backend.service.transport;

import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.model.TransportCapabilities;

public interface TransportProvider {

    /**
     * Returns the transport type.
     */
    TransportType getTransportType();

    /**
     * Checks if this transport is physically available on the host device.
     */
    boolean isAvailable();

    /**
     * Checks if the specific recipient is reachable through this transport.
     */
    boolean isReachable(com.offlinemesh.backend.entity.User recipient);

    /**
     * Retrieves the current capabilities of this transport.
     */
    TransportCapabilities getCapabilities();

    /**
     * Connects to the underlying transport network.
     */
    void connect();

    /**
     * Disconnects from the underlying transport network.
     */
    void disconnect();

    /**
     * Sends data over the established route.
     */
    boolean sendData(com.offlinemesh.backend.entity.CommunicationRoute route, Object data);
    
    /**
     * Priority of this transport. Lower number means higher priority.
     */
    int getPriority();
}
