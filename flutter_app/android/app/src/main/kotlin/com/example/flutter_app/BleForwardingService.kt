package com.example.flutter_app

import android.util.Log
import com.example.flutter_app.protocol.BleMessage
import java.util.LinkedHashMap

class BleForwardingService(
    private val localId: String,
    private val onDeliverToFlutter: (BleMessage) -> Unit,
    private val onForwardToMesh: (BleMessage) -> Unit,
    private val onAckReceived: (String) -> Unit = {}
) {
    companion object {
        const val TAG = "BleForwarding"
        const val MAX_CACHE_SIZE = 200
        const val MAX_TTL: Byte = 3
    }

    // LRU Cache for recently seen messages
    private val recentlySeenMessages = object : LinkedHashMap<String, Long>(MAX_CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: Map.Entry<String, Long>): Boolean {
            return size > MAX_CACHE_SIZE
        }
    }

    fun processMessage(message: BleMessage) {
        // 1. Loop / Duplicate Prevention
        if (recentlySeenMessages.containsKey(message.messageId)) {
            Log.d(TAG, "Dropping duplicate message: ${message.messageId}")
            return
        }
        recentlySeenMessages[message.messageId] = System.currentTimeMillis()

        // 1b. Intercept ACKs
        if (message.type == com.example.flutter_app.protocol.BlePacketType.ACK) {
            val ackedMessageId = String(message.payload)
            onAckReceived(ackedMessageId)
            
            if (message.destId == localId) {
                Log.d(TAG, "Received ACK for $ackedMessageId at final destination")
                return // Consumed
            }
        }

        // 2. Check if local recipient
        if (message.destId == localId && message.type == com.example.flutter_app.protocol.BlePacketType.MESSAGE) {
            Log.d(TAG, "Delivering message ${message.messageId} to Flutter")
            onDeliverToFlutter(message)
            
            // Generate and send ACK back to sender
            val ackId = "ACK-${message.messageId}"
            val ackMessage = BleMessage(
                type = com.example.flutter_app.protocol.BlePacketType.ACK,
                messageId = ackId,
                sourceId = localId,
                destId = message.sourceId,
                senderId = localId,
                ttl = MAX_TTL,
                payload = message.messageId.toByteArray()
            )
            markAsSeen(ackId) // So we don't bounce our own ACK
            onForwardToMesh(ackMessage)
            return
        }

        // 3. TTL Check & Decrement
        if (message.ttl <= 1) {
            Log.d(TAG, "Dropping message ${message.messageId} due to TTL expiry")
            return
        }

        val forwardedMessage = message.copy(
            ttl = (message.ttl - 1).toByte(),
            senderId = localId
        )

        Log.d(TAG, "Forwarding message ${message.messageId} (TTL: ${forwardedMessage.ttl})")
        onForwardToMesh(forwardedMessage)
    }

    fun markAsSeen(messageId: String) {
        recentlySeenMessages[messageId] = System.currentTimeMillis()
    }

    fun clearCache() {
        recentlySeenMessages.clear()
    }
}
