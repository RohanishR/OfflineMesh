package com.example.flutter_app.protocol

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

class BleReassemblyBuffer {
    companion object {
        const val TAG = "BleReassembly"
        const val TIMEOUT_MS = 30_000L // 30 seconds
        const val MAX_CONCURRENT_REASSEMBLIES = 20
    }

    private data class TransferState(
        val type: BlePacketType,
        val totalChunks: Int,
        val timestamp: Long,
        val messageId: String,
        val sourceId: String,
        val destId: String,
        val senderId: String,
        val ttl: Byte,
        val chunks: Array<ByteArray?>
    ) {
        fun isComplete(): Boolean {
            return chunks.all { it != null }
        }

        fun assemble(): BleMessage {
            var totalSize = 0
            for (chunk in chunks) {
                if (chunk == null) throw IllegalStateException("Cannot assemble incomplete message")
                totalSize += chunk.size
            }
            val result = ByteArray(totalSize)
            var offset = 0
            for (chunk in chunks) {
                System.arraycopy(chunk!!, 0, result, offset, chunk.size)
                offset += chunk.size
            }
            return BleMessage(
                type = type,
                messageId = messageId,
                sourceId = sourceId,
                destId = destId,
                senderId = senderId,
                ttl = ttl,
                payload = result
            )
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false

            other as TransferState

            if (totalChunks != other.totalChunks) return false
            if (timestamp != other.timestamp) return false
            if (messageId != other.messageId) return false
            if (!chunks.contentEquals(other.chunks)) return false

            return true
        }

        override fun hashCode(): Int {
            var result = totalChunks
            result = 31 * result + timestamp.hashCode()
            result = 31 * result + messageId.hashCode()
            result = 31 * result + chunks.contentHashCode()
            return result
        }
    }

    // Maps transferId -> TransferState
    private val activeTransfers = ConcurrentHashMap<Int, TransferState>()

    // Optional listener to bubble up complete messages
    var onMessageComplete: ((BleMessage) -> Unit)? = null

    /**
     * Feed a valid packet into the reassembly buffer.
     * Returns the full BleMessage if this chunk completes the transfer, else null.
     */
    fun processPacket(packet: BlePacket): BleMessage? {
        cleanupExpired()

        if (packet.totalChunks == 1 && packet.chunkIndex == 0) {
            // Fast path for single-chunk messages
            val msg = BleMessage(
                type = packet.type,
                messageId = packet.messageId,
                sourceId = packet.sourceId,
                destId = packet.destId,
                senderId = packet.senderId,
                ttl = packet.ttl,
                payload = packet.payload
            )
            onMessageComplete?.invoke(msg)
            return msg
        }

        var state = activeTransfers[packet.transferId]
        
        if (state == null) {
            // Enforce chunk 0 comes first
            if (packet.chunkIndex != 0) {
                Log.w(TAG, "Rejecting orphaned chunk ${packet.chunkIndex} for transfer ${packet.transferId}")
                return null
            }
            
            // Prevent too many concurrent transfers
            if (activeTransfers.size >= MAX_CONCURRENT_REASSEMBLIES) {
                Log.w(TAG, "Dropping packet. Too many concurrent reassemblies.")
                return null
            }
            state = TransferState(
                type = packet.type,
                totalChunks = packet.totalChunks,
                timestamp = System.currentTimeMillis(),
                messageId = packet.messageId,
                sourceId = packet.sourceId,
                destId = packet.destId,
                senderId = packet.senderId,
                ttl = packet.ttl,
                chunks = arrayOfNulls(packet.totalChunks)
            )
            activeTransfers[packet.transferId] = state
        } else {
            // Validation check: ensure totalChunks matches initial declaration
            if (state.totalChunks != packet.totalChunks) {
                Log.w(TAG, "Packet totalChunks mismatch. Expected ${state.totalChunks}, got ${packet.totalChunks}")
                return null
            }
            // Cannot receive chunk 0 again for the same transferId
            if (packet.chunkIndex == 0 && state.chunks[0] != null) {
                Log.w(TAG, "Duplicate chunk 0 received for transfer ${packet.transferId}")
                return null
            }
        }

        // Store chunk if not already present (duplicate prevention)
        if (state.chunks[packet.chunkIndex] == null) {
            state.chunks[packet.chunkIndex] = packet.payload
        } else {
            Log.d(TAG, "Duplicate chunk received for transfer ${packet.transferId}, index ${packet.chunkIndex}")
        }

        if (state.isComplete()) {
            activeTransfers.remove(packet.transferId)
            val fullMessage = state.assemble()
            onMessageComplete?.invoke(fullMessage)
            return fullMessage
        }

        return null
    }

    private fun cleanupExpired() {
        val now = System.currentTimeMillis()
        val toRemove = mutableListOf<Int>()
        for ((id, state) in activeTransfers) {
            if (now - state.timestamp > TIMEOUT_MS) {
                toRemove.add(id)
            }
        }
        for (id in toRemove) {
            Log.w(TAG, "Reassembly timed out for transfer $id")
            activeTransfers.remove(id)
        }
    }
    
    fun clear() {
        activeTransfers.clear()
    }
}
