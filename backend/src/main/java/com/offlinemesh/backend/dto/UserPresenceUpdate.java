package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserPresenceUpdate {
    private String offlineMeshId;
    private String status; // ONLINE, OFFLINE, TYPING, RECORDING
    private boolean isTyping;
    private boolean isRecording;
    private Instant lastSeen;
}
