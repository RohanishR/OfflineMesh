package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.CommunicationRoute;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.service.lan.LanPeerDiscovery;
import com.offlinemesh.backend.service.transport.WifiLanTransportProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class WifiLanTransportProviderTest {

    @Mock
    private LanPeerDiscovery lanPeerDiscovery;

    @Mock
    private RestTemplate restTemplate;

    @InjectMocks
    private WifiLanTransportProvider provider;

    private User recipient;
    private CommunicationRoute route;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        recipient = User.builder().offlineMeshId("OM-TARGET").build();
        route = CommunicationRoute.builder()
                .recipient(recipient)
                .transportType(TransportType.WIFI_LAN)
                .build();
    }

    @Test
    void testIsReachable_True() {
        when(lanPeerDiscovery.isPeerReachable("OM-TARGET")).thenReturn(true);
        assertTrue(provider.isReachable(recipient));
    }

    @Test
    void testIsReachable_False() {
        when(lanPeerDiscovery.isPeerReachable("OM-TARGET")).thenReturn(false);
        assertFalse(provider.isReachable(recipient));
    }

    @Test
    void testSendData_Success() {
        when(lanPeerDiscovery.getPeerAddress("OM-TARGET")).thenReturn("http://192.168.1.10:8080");
        when(restTemplate.postForEntity(eq("http://192.168.1.10:8080/api/lan/messages"), any(HttpEntity.class), eq(Void.class)))
                .thenReturn(new ResponseEntity<>(HttpStatus.OK));

        boolean success = provider.sendData(route, "testData");
        assertTrue(success);
    }

    @Test
    void testSendData_PeerNotFound() {
        when(lanPeerDiscovery.getPeerAddress("OM-TARGET")).thenReturn(null);

        boolean success = provider.sendData(route, "testData");
        assertFalse(success);
        verify(restTemplate, never()).postForEntity(anyString(), any(), any());
    }

    @Test
    void testSendData_HttpError() {
        when(lanPeerDiscovery.getPeerAddress("OM-TARGET")).thenReturn("http://192.168.1.10:8080");
        when(restTemplate.postForEntity(eq("http://192.168.1.10:8080/api/lan/messages"), any(HttpEntity.class), eq(Void.class)))
                .thenReturn(new ResponseEntity<>(HttpStatus.INTERNAL_SERVER_ERROR));

        boolean success = provider.sendData(route, "testData");
        assertFalse(success);
    }
}
