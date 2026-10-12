package com.example.flutter_app

import com.example.flutter_app.protocol.BleMessage
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class BleForwardingServiceTest {

    private lateinit var forwardingService: BleForwardingService
    private var deliveredMessage: BleMessage? = null
    private var forwardedMessage: BleMessage? = null

    @Before
    fun setup() {
        deliveredMessage = null
        forwardedMessage = null
        forwardingService = BleForwardingService(
            localId = "deviceB",
            onDeliverToFlutter = { msg -> deliveredMessage = msg },
            onForwardToMesh = { msg -> forwardedMessage = msg }
        )
    }

    @Test
    fun testLocalRecipientIsDelivered() {
        val msg = BleMessage(com.example.flutter_app.protocol.BlePacketType.MESSAGE, "msg1", "deviceA", "deviceB", "deviceA", 3, byteArrayOf(1,2,3))
        forwardingService.processMessage(msg)

        assertNotNull(deliveredMessage)
        assertNotNull(forwardedMessage)
        assertEquals(com.example.flutter_app.protocol.BlePacketType.ACK, forwardedMessage?.type)
        assertEquals("msg1", deliveredMessage?.messageId)
    }

    @Test
    fun testForeignRecipientIsForwardedWithTtlDecrement() {
        val msg = BleMessage(com.example.flutter_app.protocol.BlePacketType.MESSAGE, "msg2", "deviceA", "deviceC", "deviceA", 3, byteArrayOf(1,2,3))
        forwardingService.processMessage(msg)

        assertNull(deliveredMessage)
        assertNotNull(forwardedMessage)
        
        // TTL should be decremented
        assertEquals(2.toByte(), forwardedMessage?.ttl)
        // senderId should become localId
        assertEquals("deviceB", forwardedMessage?.senderId)
    }

    @Test
    fun testTtlExpiryIsDropped() {
        // TTL is 1, decrementing would make it 0, so it shouldn't forward
        val msg = BleMessage(com.example.flutter_app.protocol.BlePacketType.MESSAGE, "msg3", "deviceA", "deviceC", "deviceA", 1, byteArrayOf(1,2,3))
        forwardingService.processMessage(msg)

        assertNull(deliveredMessage)
        assertNull(forwardedMessage)
    }

    @Test
    fun testDuplicateMessageIsDropped() {
        val msg = BleMessage(com.example.flutter_app.protocol.BlePacketType.MESSAGE, "msg4", "deviceA", "deviceC", "deviceA", 3, byteArrayOf(1,2,3))
        forwardingService.processMessage(msg)
        
        assertNotNull(forwardedMessage)
        
        // Reset and send same message again
        forwardedMessage = null
        forwardingService.processMessage(msg)
        
        // Should drop duplicate
        assertNull(forwardedMessage)
    }
}
