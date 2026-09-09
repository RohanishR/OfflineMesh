package com.offlinemesh.backend.exception;

public class UnauthorizedMessagingException extends RuntimeException {
    public UnauthorizedMessagingException(String message) {
        super(message);
    }
}
