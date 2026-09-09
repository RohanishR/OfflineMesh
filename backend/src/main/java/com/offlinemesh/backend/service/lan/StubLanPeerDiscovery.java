package com.offlinemesh.backend.service.lan;

import com.offlinemesh.backend.entity.User;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * A stub implementation for LAN discovery.
 * In a real environment, this would use mDNS/ZeroConf or Wi-Fi Direct.
 */
@Service
public class StubLanPeerDiscovery implements LanPeerDiscovery {

    // Maps offlineMeshId -> reachable LAN URL
    private final Map<String, String> reachablePeers = new ConcurrentHashMap<>();

    @Override
    public boolean isPeerReachable(String targetOfflineMeshId) {
        return reachablePeers.containsKey(targetOfflineMeshId);
    }

    @Override
    public String getPeerAddress(String targetOfflineMeshId) {
        return reachablePeers.get(targetOfflineMeshId);
    }

    @Override
    public void registerSelf(User currentUser) {
        // In this stub, we don't automatically discover ourselves on the actual network, 
        // we just simulate it. If we wanted to simulate a peer:
        // reachablePeers.put(currentUser.getOfflineMeshId(), "http://192.168.1.100:8080");
    }

    // For testing purposes
    public void addMockPeer(String targetOfflineMeshId, String address) {
        reachablePeers.put(targetOfflineMeshId, address);
    }

    public void removeMockPeer(String targetOfflineMeshId) {
        reachablePeers.remove(targetOfflineMeshId);
    }
}
