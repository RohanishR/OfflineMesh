package com.example.flutter_app.protocol

import org.junit.Assert.*
import org.junit.Test

class BlePacketCodecTest {

    @Test
    fun testEncodeDecode() {
        val payload = "Hello World".toByteArray(Charsets.UTF_8)
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.MESSAGE,
            flags = 0,
            transferId = 12345678,
            chunkIndex = 5,
            totalChunks = 10,
            payloadLength = payload.size,
            payload = payload
        )

        val encoded = BlePacketCodec.encode(packet)
        assertEquals(BlePacket.BASE_HEADER_SIZE + payload.size, encoded.size)

        val decoded = BlePacketCodec.decode(encoded)
        assertEquals(packet, decoded)
    }

    @Test
    fun testEmptyPayload() {
        val payload = ByteArray(0)
        val packet = BlePacket(
            version = 1,
            type = BlePacketType.ACK,
            flags = 1,
            transferId = 87654321,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = 0,
            messageId = "msg1",
            sourceId = "A",
            destId = "B",
            senderId = "A",
            payload = payload
        )

        val encoded = BlePacketCodec.encode(packet)
        // Base header + 4 size bytes + string lengths
        val expectedSize = BlePacket.BASE_HEADER_SIZE + 4 + 4 + 1 + 1 + 1
        assertEquals(expectedSize, encoded.size)

        val decoded = BlePacketCodec.decode(encoded)
        assertEquals(packet, decoded)
    }

    @Test(expected = IllegalArgumentException::class)
    fun testDecodeSmallBuffer() {
        val small = ByteArray(5)
        BlePacketCodec.decode(small)
    }
}
