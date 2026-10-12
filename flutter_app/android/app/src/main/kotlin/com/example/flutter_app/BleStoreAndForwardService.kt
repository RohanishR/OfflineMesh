package com.example.flutter_app

import android.content.Context

import android.util.Log
import com.example.flutter_app.protocol.BleMessage
import com.example.flutter_app.protocol.BlePacketType
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

data class QueuedMessage(
    val message: BleMessage,
    val createdAt: Long,
    var retryCount: Int,
    var nextRetryTime: Long
)

class BleStoreAndForwardService(
    baseDir: File,
    private val onForward: (BleMessage) -> Unit
) {
    companion object {
        const val TAG = "BleStoreForward"
        const val MAX_QUEUE_SIZE = 500
        const val MAX_RETRIES = 5
        const val EXPIRY_TIME_MS = 24L * 60 * 60 * 1000 // 24 hours
        const val INITIAL_BACKOFF_MS = 5000L // 5 seconds
    }

    private val queueDir = File(baseDir, "ble_queue").apply {
        if (!exists()) mkdirs()
    }

    private var retryExecutor: ScheduledExecutorService? = null
    private var retryTask: ScheduledFuture<*>? = null

    /**
     * Queues a message for offline delivery.
     */
    fun queueMessage(message: BleMessage) {
        if (message.messageId.isEmpty() || message.destId.isEmpty() || message.destId == "mesh") {
            return // Do not queue invalid or purely broadcast messages
        }

        val file = File(queueDir, "${message.messageId}.json")
        if (file.exists()) {
            return // Already queued
        }

        enforceQueueLimits()

        val queued = QueuedMessage(
            message = message,
            createdAt = System.currentTimeMillis(),
            retryCount = 0,
            nextRetryTime = System.currentTimeMillis() + INITIAL_BACKOFF_MS
        )

        saveToFile(file, queued)
        Log.d(TAG, "Queued message ${message.messageId} for offline delivery to ${message.destId}")
    }

    /**
     * Called when a route to destId becomes available.
     * Immediately attempts to forward all queued messages for this destination.
     */
    fun onRouteAvailable(destId: String) {
        val files = queueDir.listFiles() ?: return
        val now = System.currentTimeMillis()
        var attempted = 0

        for (file in files) {
            val queued = loadFromFile(file) ?: continue

            // Prune expired
            if (now - queued.createdAt > EXPIRY_TIME_MS) {
                file.delete()
                continue
            }

            if (queued.message.destId == destId) {
                if (queued.retryCount < MAX_RETRIES) {
                    Log.d(TAG, "Route available! Forwarding queued message ${queued.message.messageId} to $destId")
                    
                    // Increment retry
                    queued.retryCount++
                    queued.nextRetryTime = now + (INITIAL_BACKOFF_MS * Math.pow(2.0, queued.retryCount.toDouble())).toLong()
                    saveToFile(file, queued)
                    
                    onForward(queued.message)
                    attempted++
                } else {
                    Log.d(TAG, "Message ${queued.message.messageId} exhausted retries. Dropping.")
                    file.delete()
                }
            }
        }

        if (attempted > 0) {
            Log.d(TAG, "Flushed $attempted messages for $destId")
        }
    }

    /**
     * Deletes a message from the queue upon receiving a delivery ACK.
     */
    fun onAckReceived(messageId: String) {
        val file = File(queueDir, "$messageId.json")
        if (file.exists()) {
            file.delete()
            Log.d(TAG, "Received ACK. Removed queued message $messageId")
        }
    }

    /**
     * Starts the exponential backoff retry loop. Only call when BLE connections > 0.
     */
    fun startRetryTimer() {
        if (retryTask != null && !retryTask!!.isCancelled) return
        
        if (retryExecutor == null || retryExecutor!!.isShutdown) {
            retryExecutor = Executors.newSingleThreadScheduledExecutor()
        }

        Log.d(TAG, "Starting fallback retry timer (connections active)")
        retryTask = retryExecutor!!.scheduleWithFixedDelay({
            processRetries()
        }, INITIAL_BACKOFF_MS, INITIAL_BACKOFF_MS, TimeUnit.MILLISECONDS)
    }

    /**
     * Stops the retry loop to save battery when disconnected.
     */
    fun stopRetryTimer() {
        Log.d(TAG, "Stopping fallback retry timer (no connections)")
        retryTask?.cancel(false)
        retryTask = null
    }

    private fun processRetries() {
        val files = queueDir.listFiles() ?: return
        val now = System.currentTimeMillis()

        for (file in files) {
            val queued = loadFromFile(file) ?: continue

            if (now - queued.createdAt > EXPIRY_TIME_MS) {
                file.delete()
                continue
            }

            if (queued.retryCount >= MAX_RETRIES) {
                file.delete()
                continue
            }

            if (now >= queued.nextRetryTime) {
                Log.d(TAG, "Timer trigger: Retrying message ${queued.message.messageId} (Attempt ${queued.retryCount + 1})")
                
                queued.retryCount++
                queued.nextRetryTime = now + (INITIAL_BACKOFF_MS * Math.pow(2.0, queued.retryCount.toDouble())).toLong()
                saveToFile(file, queued)
                
                onForward(queued.message)
            }
        }
    }

    private fun enforceQueueLimits() {
        val files = queueDir.listFiles() ?: return
        if (files.size < MAX_QUEUE_SIZE) return

        // Delete oldest file
        files.minByOrNull { it.lastModified() }?.delete()
    }

    private fun saveToFile(file: File, queuedMessage: QueuedMessage) {
        try {
            java.io.DataOutputStream(java.io.FileOutputStream(file)).use { dos ->
                val msg = queuedMessage.message
                dos.writeUTF(msg.messageId)
                dos.writeUTF(msg.sourceId)
                dos.writeUTF(msg.destId)
                dos.writeUTF(msg.senderId)
                dos.writeByte(msg.ttl.toInt())
                dos.writeInt(msg.payload.size)
                dos.write(msg.payload)

                dos.writeLong(queuedMessage.createdAt)
                dos.writeInt(queuedMessage.retryCount)
                dos.writeLong(queuedMessage.nextRetryTime)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save queued message", e)
        }
    }

    private fun loadFromFile(file: File): QueuedMessage? {
        try {
            java.io.DataInputStream(java.io.FileInputStream(file)).use { dis ->
                val messageId = dis.readUTF()
                val sourceId = dis.readUTF()
                val destId = dis.readUTF()
                val senderId = dis.readUTF()
                val ttl = dis.readByte()
                val payloadSize = dis.readInt()
                val payload = ByteArray(payloadSize)
                dis.readFully(payload)

                val bleMessage = BleMessage(
                    type = BlePacketType.MESSAGE,
                    messageId = messageId,
                    sourceId = sourceId,
                    destId = destId,
                    senderId = senderId,
                    ttl = ttl,
                    payload = payload
                )

                val createdAt = dis.readLong()
                val retryCount = dis.readInt()
                val nextRetryTime = dis.readLong()

                return QueuedMessage(
                    message = bleMessage,
                    createdAt = createdAt,
                    retryCount = retryCount,
                    nextRetryTime = nextRetryTime
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load queued message. Deleting corrupted file.", e)
            file.delete()
            return null
        }
    }
}
