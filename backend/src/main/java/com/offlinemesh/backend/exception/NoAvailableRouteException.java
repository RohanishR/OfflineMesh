package com.offlinemesh.backend.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.SERVICE_UNAVAILABLE)
public class NoAvailableRouteException extends RuntimeException {
    public NoAvailableRouteException(String message) {
        super(message);
    }
}
