package com.example.flutter_app.protocol

import java.util.Arrays

data class BlePacket(
    val version: Byte = 1,
    val type: BlePacketType,
    val ttl: Byte = 3,
    val flags: Byte = 0,
    val transferId: Int, // 4-byte unique ID for this chunk sequence
    val chunkIndex: Int, // 2-byte unsigned represented as Int
    val totalChunks: Int, // 2-byte unsigned represented as Int
    val payloadLength: Int, // 2-byte unsigned represented as Int
    val messageId: String = "", 
    val sourceId: String = "",
    val destId: String = "",
    val senderId: String = "",
    val payload: ByteArray // The actual data
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as BlePacket

        if (version != other.version) return false
        if (type != other.type) return false
        if (ttl != other.ttl) return false
        if (flags != other.flags) return false
        if (transferId != other.transferId) return false
        if (chunkIndex != other.chunkIndex) return false
        if (totalChunks != other.totalChunks) return false
        if (payloadLength != other.payloadLength) return false
        if (messageId != other.messageId) return false
        if (sourceId != other.sourceId) return false
        if (destId != other.destId) return false
        if (senderId != other.senderId) return false
        if (!Arrays.equals(payload, other.payload)) return false

        return true
    }

    override fun hashCode(): Int {
        var result = version.toInt()
        result = 31 * result + type.hashCode()
        result = 31 * result + ttl
        result = 31 * result + flags
        result = 31 * result + transferId
        result = 31 * result + chunkIndex
        result = 31 * result + totalChunks
        result = 31 * result + payloadLength
        result = 31 * result + messageId.hashCode()
        result = 31 * result + sourceId.hashCode()
        result = 31 * result + destId.hashCode()
        result = 31 * result + senderId.hashCode()
        result = 31 * result + Arrays.hashCode(payload)
        return result
    }
    
    companion object {
        const val BASE_HEADER_SIZE = 14 // 1+1+1+1+4+2+2+2
        const val CURRENT_VERSION: Byte = 1
    }
}
