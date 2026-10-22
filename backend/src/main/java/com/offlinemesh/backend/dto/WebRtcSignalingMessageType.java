package com.offlinemesh.backend.dto;

public enum WebRtcSignalingMessageType {
    CALL_OFFER,
    CALL_ANSWER,
    ICE_CANDIDATE,
    CALL_REJECT,
    CALL_CANCEL,
    CALL_END,
    CALL_FAILED,
    CALL_BUSY
}
