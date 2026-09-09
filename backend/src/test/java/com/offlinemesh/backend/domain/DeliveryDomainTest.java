package com.offlinemesh.backend.domain;

import com.offlinemesh.backend.entity.Delivery;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.TransportType;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class DeliveryDomainTest {

    @Test
    void testDeliveryBuilder() {
        User sender = User.builder().id(UUID.randomUUID()).username("sender").build();
        User recipient = User.builder().id(UUID.randomUUID()).username("recipient").build();
        Message message = Message.builder().id(UUID.randomUUID()).build();
        
        UUID deliveryId = UUID.randomUUID();
        Delivery delivery = Delivery.builder()
                .id(deliveryId)
                .message(message)
                .sender(sender)
                .recipient(recipient)
                .selectedTransport(TransportType.BLE_MESH)
                .status(MessageStatus.FAILED)
                .retryCount(2)
                .build();

        assertNotNull(delivery.getId());
        assertEquals(deliveryId, delivery.getId());
        assertEquals(message, delivery.getMessage());
        assertEquals(TransportType.BLE_MESH, delivery.getSelectedTransport());
        assertEquals(MessageStatus.FAILED, delivery.getStatus());
        assertEquals(2, delivery.getRetryCount());
    }
}
