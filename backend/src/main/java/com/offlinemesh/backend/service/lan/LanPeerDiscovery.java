package com.offlinemesh.backend.service.lan;

import com.offlinemesh.backend.entity.User;

public interface LanPeerDiscovery {

    /**
     * Checks if a peer is reachable on the local network.
     */
    boolean isPeerReachable(String targetOfflineMeshId);

    /**
     * Retrieves the LAN address/URL of the peer.
     */
    String getPeerAddress(String targetOfflineMeshId);

    /**
     * Registers the current device on the LAN.
     */
    void registerSelf(User currentUser);
}
