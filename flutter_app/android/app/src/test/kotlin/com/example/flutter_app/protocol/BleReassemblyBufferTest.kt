package com.example.flutter_app.protocol

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class BleReassemblyBufferTest {

    private lateinit var buffer: BleReassemblyBuffer

    @Before
    fun setup() {
        buffer = BleReassemblyBuffer()
    }

    @Test
    fun testSingleChunkMessage() {
        val payload = "Hello".toByteArray()
        val packet = BlePacket(
            type = BlePacketType.MESSAGE,
            transferId = 1,
            chunkIndex = 0,
            totalChunks = 1,
            payloadLength = payload.size,
            messageId = "msg1",
            sourceId = "A",
            destId = "B",
            senderId = "A",
            payload = payload
        )

        var completedPayload: BleMessage? = null
        buffer.onMessageComplete = {
            completedPayload = it
        }

        val result = buffer.processPacket(packet)
        assertNotNull(result)
        assertArrayEquals(payload, result?.payload)
        assertArrayEquals(payload, completedPayload?.payload)
    }

    @Test
    fun testMultiChunkMessage() {
        val p1 = "Hello ".toByteArray()
        val p2 = "World".toByteArray()
        val transferId = 2

        val pkt1 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 0, totalChunks = 2, payloadLength = p1.size,
            messageId = "msg2", sourceId = "A", destId = "B", senderId = "A", payload = p1
        )
        val pkt2 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 1, totalChunks = 2, payloadLength = p2.size, payload = p2
        )

        var completedPayload: BleMessage? = null
        buffer.onMessageComplete = {
            completedPayload = it
        }

        val r1 = buffer.processPacket(pkt1)
        assertNull(r1) // Incomplete
        assertNull(completedPayload)

        val r2 = buffer.processPacket(pkt2)
        assertNotNull(r2)
        val expected = "Hello World".toByteArray()
        assertArrayEquals(expected, r2?.payload)
        assertArrayEquals(expected, completedPayload?.payload)
    }

    @Test
    fun testOutOfOrderChunksRejected() {
        // Enforcing chunk 0 comes first, out of order chunk should be rejected
        val p1 = "A".toByteArray()
        val p2 = "B".toByteArray()
        val transferId = 3

        val pkt1 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 0, totalChunks = 2, payloadLength = p1.size, 
            messageId = "msg3", sourceId = "A", destId = "B", senderId = "A", payload = p1
        )
        val pkt2 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 1, totalChunks = 2, payloadLength = p2.size, payload = p2
        )

        val r1 = buffer.processPacket(pkt2) // Process 2nd chunk first - REJECTED
        assertNull(r1)
        val r2 = buffer.processPacket(pkt1) // Process 1st chunk - STARTED
        assertNull(r2) 
        val r3 = buffer.processPacket(pkt2) // Process 2nd chunk again
        assertNotNull(r3)
        assertArrayEquals("AB".toByteArray(), r3?.payload)
    }

    @Test
    fun testDuplicateChunksIgnored() {
        val p1 = "A".toByteArray()
        val p2 = "B".toByteArray()
        val transferId = 4

        val pkt1 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 0, totalChunks = 2, payloadLength = p1.size, 
            messageId = "msg4", sourceId = "A", destId = "B", senderId = "A", payload = p1
        )
        
        val pkt2 = BlePacket(
            type = BlePacketType.MESSAGE, transferId = transferId,
            chunkIndex = 1, totalChunks = 2, payloadLength = p2.size, payload = p2
        )

        buffer.processPacket(pkt1)
        buffer.processPacket(pkt1) // Duplicate should be safely ignored
        val res = buffer.processPacket(pkt2)
        assertNotNull(res)
    }
}
