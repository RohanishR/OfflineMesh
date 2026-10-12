package com.example.flutter_app.protocol

class BlePacketValidator {
    companion object {
        const val MAX_CHUNKS = 10000 // To prevent OOM / massive arrays
        const val MAX_PAYLOAD_SIZE = 1024 // One packet payload limit

        fun validate(packet: BlePacket): Boolean {
            if (packet.version != BlePacket.CURRENT_VERSION) {
                return false
            }
            if (packet.type == BlePacketType.UNKNOWN) {
                return false
            }
            if (packet.totalChunks <= 0 || packet.totalChunks > MAX_CHUNKS) {
                return false
            }
            if (packet.chunkIndex < 0 || packet.chunkIndex >= packet.totalChunks) {
                return false
            }
            if (packet.payloadLength < 0 || packet.payloadLength > MAX_PAYLOAD_SIZE) {
                return false
            }
            if (packet.payload.size != packet.payloadLength) {
                return false
            }
            
            // Chunk 0 must have routing info if it's a message
            if (packet.type == BlePacketType.MESSAGE && packet.chunkIndex == 0) {
                if (packet.messageId.isEmpty() || packet.sourceId.isEmpty() || packet.destId.isEmpty()) {
                    return false
                }
            }
            
            return true
        }
    }
}
