package com.offlinemesh.backend.model;

import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import lombok.Builder;
import lombok.Data;

import java.time.Instant;
import java.util.Map;
import java.util.Set;

@Data
@Builder
public class TransportCapabilities {
    private TransportType transportType;
    private boolean available;
    private boolean connected;
    private int latency;
    private int bandwidth;
    private Instant lastChecked;
    private Set<MessageType> supportedCommunicationTypes;
    private Map<String, Object> metadata;
}
