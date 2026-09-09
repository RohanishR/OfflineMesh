package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.CommunicationRoute;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.exception.NoAvailableRouteException;
import com.offlinemesh.backend.model.TransportCapabilities;
import com.offlinemesh.backend.service.transport.TransportProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RoutingServiceTest {

    private TransportAvailabilityService availabilityService;
    private RoutingService routingService;
    
    private TransportProvider internetProvider;
    private TransportProvider wifiProvider;
    private TransportProvider bluetoothProvider;
    private TransportProvider bleMeshProvider;

    private User sender;
    private User recipient;

    @BeforeEach
    void setUp() {
        sender = User.builder().id(UUID.randomUUID()).build();
        recipient = User.builder().id(UUID.randomUUID()).build();

        availabilityService = mock(TransportAvailabilityService.class);

        internetProvider = mock(TransportProvider.class);
        when(internetProvider.getPriority()).thenReturn(4);
        when(internetProvider.getTransportType()).thenReturn(TransportType.INTERNET);
        when(internetProvider.isReachable(any())).thenReturn(true);
        when(internetProvider.sendData(any(), any())).thenReturn(true);
        when(internetProvider.getCapabilities()).thenReturn(TransportCapabilities.builder()
                .supportedCommunicationTypes(Set.of(MessageType.TEXT, MessageType.IMAGE, MessageType.VIDEO, MessageType.AUDIO, MessageType.FILE, MessageType.VOICE_CALL, MessageType.VIDEO_CALL))
                .build());

        wifiProvider = mock(TransportProvider.class);
        when(wifiProvider.getPriority()).thenReturn(1);
        when(wifiProvider.getTransportType()).thenReturn(TransportType.WIFI_LAN);
        when(wifiProvider.isReachable(any())).thenReturn(true);
        when(wifiProvider.sendData(any(), any())).thenReturn(true);
        when(wifiProvider.getCapabilities()).thenReturn(TransportCapabilities.builder()
                .supportedCommunicationTypes(Set.of(MessageType.TEXT, MessageType.IMAGE, MessageType.VIDEO, MessageType.AUDIO, MessageType.FILE))
                .build());

        bluetoothProvider = mock(TransportProvider.class);
        when(bluetoothProvider.getPriority()).thenReturn(2);
        when(bluetoothProvider.getTransportType()).thenReturn(TransportType.BLUETOOTH);
        when(bluetoothProvider.isReachable(any())).thenReturn(true);
        when(bluetoothProvider.sendData(any(), any())).thenReturn(true);
        when(bluetoothProvider.getCapabilities()).thenReturn(TransportCapabilities.builder()
                .supportedCommunicationTypes(Set.of(MessageType.TEXT, MessageType.FILE))
                .build());

        bleMeshProvider = mock(TransportProvider.class);
        when(bleMeshProvider.getPriority()).thenReturn(3);
        when(bleMeshProvider.getTransportType()).thenReturn(TransportType.BLE_MESH);
        when(bleMeshProvider.isReachable(any())).thenReturn(true);
        when(bleMeshProvider.sendData(any(), any())).thenReturn(true);
        when(bleMeshProvider.getCapabilities()).thenReturn(TransportCapabilities.builder()
                .supportedCommunicationTypes(Set.of(MessageType.TEXT))
                .build());

        routingService = new RoutingService(availabilityService);
    }

    @Test
    void test1_OnlyInternetAvailable_SelectsInternet() {
        when(availabilityService.getAvailableTransports()).thenReturn(Collections.singletonList(internetProvider));

        CommunicationRoute route = routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test");

        assertEquals(TransportType.INTERNET, route.getTransportType());
        verify(internetProvider).connect();
    }

    @Test
    void test2_WifiAndInternetAvailable_SelectsWifi() {
        when(availabilityService.getAvailableTransports()).thenReturn(Arrays.asList(internetProvider, wifiProvider));

        CommunicationRoute route = routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test");

        assertEquals(TransportType.WIFI_LAN, route.getTransportType());
    }

    @Test
    void test3_BluetoothAndInternetAvailable_WifiUnavailable_SelectsBluetooth() {
        when(availabilityService.getAvailableTransports()).thenReturn(Arrays.asList(internetProvider, bluetoothProvider));

        CommunicationRoute route = routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test");

        assertEquals(TransportType.BLUETOOTH, route.getTransportType());
    }

    @Test
    void test4_NoTransportAvailable_ThrowsException() {
        when(availabilityService.getAvailableTransports()).thenReturn(Collections.emptyList());

        assertThrows(NoAvailableRouteException.class, () -> routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test"));
    }

    @Test
    void test5_WifiFailsSend_FallsBackToInternet() {
        when(availabilityService.getAvailableTransports()).thenReturn(Arrays.asList(internetProvider, wifiProvider));
        when(wifiProvider.sendData(any(), any())).thenReturn(false); // Fail sending on Wi-Fi

        CommunicationRoute route = routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test");

        // Should fallback to Internet which returns true
        assertEquals(TransportType.INTERNET, route.getTransportType());
        verify(wifiProvider).connect();
        verify(wifiProvider).sendData(any(), any());
        verify(internetProvider).connect();
        verify(internetProvider).sendData(any(), any());
    }

    @Test
    void test6_WifiReachableFalse_SelectsInternet() {
        when(availabilityService.getAvailableTransports()).thenReturn(Arrays.asList(internetProvider, wifiProvider));
        when(wifiProvider.isReachable(any())).thenReturn(false);

        CommunicationRoute route = routingService.routeAndSend(sender, recipient, MessageType.TEXT, "test");

        assertEquals(TransportType.INTERNET, route.getTransportType());
        verify(wifiProvider, never()).connect();
    }
}
