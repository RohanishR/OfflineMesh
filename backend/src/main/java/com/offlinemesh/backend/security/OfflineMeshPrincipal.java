package com.offlinemesh.backend.security;

import com.offlinemesh.backend.entity.User;
import lombok.Getter;

import java.security.Principal;

/**
 * Custom Principal for WebSocket routing that exposes the offlineMeshId
 * instead of the username.
 */
@Getter
public class OfflineMeshPrincipal implements Principal {

    private final User user;

    public OfflineMeshPrincipal(User user) {
        this.user = user;
    }

    @Override
    public String getName() {
        return user.getOfflineMeshId();
    }
}
