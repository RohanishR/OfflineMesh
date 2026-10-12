package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WebRtcSignalingMessage {
    private String id;
    private String sessionId;
    private String senderOfflineMeshId;
    private String recipientOfflineMeshId;
    private WebRtcSignalingMessageType type;
    
    // SDP format (could be JSON string from flutter_webrtc RTCSessionDescription)
    private String sdp;
    
    // ICE Candidate format (JSON string from flutter_webrtc RTCIceCandidate)
    private String iceCandidate;
    
    private LocalDateTime timestamp;
}
