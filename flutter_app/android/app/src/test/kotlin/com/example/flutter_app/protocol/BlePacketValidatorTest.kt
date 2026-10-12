package com.example.flutter_app.protocol

import org.junit.Assert.*
import org.junit.Test

class BlePacketValidatorTest {

    @Test
    fun testValidPacket() {
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.MESSAGE,
            flags = 0,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 2,
            payloadLength = 4,
            messageId = "msg",
            sourceId = "A",
            destId = "B",
            payload = ByteArray(4)
        )
        assertTrue(BlePacketValidator.validate(packet))
    }

    @Test
    fun testInvalidVersion() {
        val packet = BlePacket(
            version = 2,
            type = BlePacketType.MESSAGE,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = 0,
            payload = ByteArray(0)
        )
        assertFalse(BlePacketValidator.validate(packet))
    }

    @Test
    fun testInvalidType() {
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.UNKNOWN,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = 0,
            payload = ByteArray(0)
        )
        assertFalse(BlePacketValidator.validate(packet))
    }

    @Test
    fun testOversizedPayload() {
        val oversized = ByteArray(BlePacketValidator.MAX_PAYLOAD_SIZE + 1)
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.MESSAGE,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = oversized.size,
            payload = oversized
        )
        assertFalse(BlePacketValidator.validate(packet))
    }

    @Test
    fun testMismatchPayloadLength() {
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.MESSAGE,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = 10,
            payload = ByteArray(5)
        )
        assertFalse(BlePacketValidator.validate(packet))
    }
}
