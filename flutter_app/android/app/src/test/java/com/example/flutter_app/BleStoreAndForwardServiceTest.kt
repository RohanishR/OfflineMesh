package com.example.flutter_app

import android.content.Context
import com.example.flutter_app.protocol.BleMessage
import com.example.flutter_app.protocol.BlePacketType
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

import java.io.File
import java.nio.file.Files

class BleStoreAndForwardServiceTest {

    private lateinit var tempDir: File
    private lateinit var service: BleStoreAndForwardService
    private val forwardedMessages = mutableListOf<BleMessage>()

    @Before
    fun setup() {
        tempDir = Files.createTempDirectory("ble_queue_test").toFile()
        service = BleStoreAndForwardService(tempDir) { msg ->
            forwardedMessages.add(msg)
        }
        forwardedMessages.clear()
    }

    @After
    fun teardown() {
        service.stopRetryTimer()
        tempDir.deleteRecursively()
    }

    private fun createMessage(id: String, destId: String = "destA"): BleMessage {
        return BleMessage(
            type = BlePacketType.MESSAGE,
            messageId = id,
            sourceId = "sourceA",
            destId = destId,
            senderId = "sourceA",
            ttl = 3,
            payload = byteArrayOf(1, 2, 3)
        )
    }

    @Test
    fun testQueueMessageStoresFile() {
        val msg = createMessage("msg1")
        service.queueMessage(msg)

        val queueDir = File(tempDir, "ble_queue")
        val msgFile = File(queueDir, "msg1.json")
        assertTrue(msgFile.exists())
    }

    @Test
    fun testDoNotQueueInvalidMessage() {
        val msg = createMessage("msg2", "mesh") // "mesh" is broadcast, shouldn't queue
        service.queueMessage(msg)

        val queueDir = File(tempDir, "ble_queue")
        val msgFile = File(queueDir, "msg2.json")
        assertFalse(msgFile.exists())
    }

    @Test
    fun testOnRouteAvailableForwardsMessages() {
        val msgA = createMessage("msgA", "destA")
        val msgB = createMessage("msgB", "destB")

        service.queueMessage(msgA)
        service.queueMessage(msgB)

        // Simulate route to destA available
        service.onRouteAvailable("destA")

        assertEquals(1, forwardedMessages.size)
        assertEquals("msgA", forwardedMessages[0].messageId)
    }

    @Test
    fun testOnAckReceivedDeletesMessage() {
        val msg = createMessage("msg_to_ack")
        service.queueMessage(msg)

        val queueDir = File(tempDir, "ble_queue")
        val msgFile = File(queueDir, "msg_to_ack.json")
        assertTrue(msgFile.exists())

        service.onAckReceived("msg_to_ack")
        assertFalse(msgFile.exists())
    }

    @Test
    fun testQueueLimitsEnforced() {
        // Queue beyond MAX_QUEUE_SIZE (500)
        // For testing, we'll just queue 501
        for (i in 1..501) {
            val msg = createMessage("msg_$i")
            service.queueMessage(msg)
            // Sleep 1ms to ensure different timestamps for eviction
            Thread.sleep(1)
        }

        val queueDir = File(tempDir, "ble_queue")
        val files = queueDir.listFiles()
        assertNotNull(files)
        assertEquals(500, files!!.size) // Maximum 500 files

        // msg_1 should be evicted since it's oldest
        val firstMsgFile = File(queueDir, "msg_1.json")
        assertFalse(firstMsgFile.exists())
    }
}
