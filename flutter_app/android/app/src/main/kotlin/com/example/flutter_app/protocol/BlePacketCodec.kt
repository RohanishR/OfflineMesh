package com.example.flutter_app.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

class BlePacketCodec {
    companion object {
        fun encode(packet: BlePacket): ByteArray {
            val isFirstChunk = packet.chunkIndex == 0
            val msgIdBytes = if (isFirstChunk) packet.messageId.toByteArray(Charsets.UTF_8) else ByteArray(0)
            val srcIdBytes = if (isFirstChunk) packet.sourceId.toByteArray(Charsets.UTF_8) else ByteArray(0)
            val destIdBytes = if (isFirstChunk) packet.destId.toByteArray(Charsets.UTF_8) else ByteArray(0)
            val senderIdBytes = if (isFirstChunk) packet.senderId.toByteArray(Charsets.UTF_8) else ByteArray(0)

            val headerSize = BlePacket.BASE_HEADER_SIZE + 
                (if (isFirstChunk) 4 + msgIdBytes.size + srcIdBytes.size + destIdBytes.size + senderIdBytes.size else 0)
                
            val totalSize = headerSize + packet.payloadLength
            val buffer = ByteBuffer.allocate(totalSize)
            buffer.order(ByteOrder.BIG_ENDIAN)

            buffer.put(packet.version)
            buffer.put(packet.type.value)
            buffer.put(packet.ttl)
            buffer.put(packet.flags)
            buffer.putInt(packet.transferId)
            
            buffer.putShort(packet.chunkIndex.toShort())
            buffer.putShort(packet.totalChunks.toShort())
            buffer.putShort(packet.payloadLength.toShort())

            if (isFirstChunk) {
                buffer.put(msgIdBytes.size.toByte())
                buffer.put(msgIdBytes)
                buffer.put(srcIdBytes.size.toByte())
                buffer.put(srcIdBytes)
                buffer.put(destIdBytes.size.toByte())
                buffer.put(destIdBytes)
                buffer.put(senderIdBytes.size.toByte())
                buffer.put(senderIdBytes)
            }

            if (packet.payloadLength > 0 && packet.payload.isNotEmpty()) {
                buffer.put(packet.payload, 0, packet.payloadLength)
            }

            return buffer.array()
        }

        fun decode(bytes: ByteArray): BlePacket {
            if (bytes.size < BlePacket.BASE_HEADER_SIZE) {
                throw IllegalArgumentException("Packet size too small for base header: ${bytes.size}")
            }

            val buffer = ByteBuffer.wrap(bytes)
            buffer.order(ByteOrder.BIG_ENDIAN)

            val version = buffer.get()
            val typeValue = buffer.get()
            val ttl = buffer.get()
            val flags = buffer.get()
            val transferId = buffer.getInt()
            
            val chunkIndex = buffer.getShort().toInt() and 0xFFFF
            val totalChunks = buffer.getShort().toInt() and 0xFFFF
            val payloadLength = buffer.getShort().toInt() and 0xFFFF

            var messageId = ""
            var sourceId = ""
            var destId = ""
            var senderId = ""
            
            val isFirstChunk = chunkIndex == 0
            
            if (isFirstChunk) {
                if (buffer.remaining() < 4) throw IllegalArgumentException("Not enough bytes for routing lengths")
                
                val msgLen = buffer.get().toInt() and 0xFF
                if (buffer.remaining() < msgLen) throw IllegalArgumentException("Corrupted messageId")
                val msgBytes = ByteArray(msgLen)
                buffer.get(msgBytes)
                messageId = String(msgBytes, Charsets.UTF_8)
                
                val srcLen = buffer.get().toInt() and 0xFF
                if (buffer.remaining() < srcLen) throw IllegalArgumentException("Corrupted sourceId")
                val srcBytes = ByteArray(srcLen)
                buffer.get(srcBytes)
                sourceId = String(srcBytes, Charsets.UTF_8)
                
                val destLen = buffer.get().toInt() and 0xFF
                if (buffer.remaining() < destLen) throw IllegalArgumentException("Corrupted destId")
                val destBytes = ByteArray(destLen)
                buffer.get(destBytes)
                destId = String(destBytes, Charsets.UTF_8)
                
                val senderLen = buffer.get().toInt() and 0xFF
                if (buffer.remaining() < senderLen) throw IllegalArgumentException("Corrupted senderId")
                val senderBytes = ByteArray(senderLen)
                buffer.get(senderBytes)
                senderId = String(senderBytes, Charsets.UTF_8)
            }

            if (buffer.remaining() < payloadLength) {
                throw IllegalArgumentException("Packet payload length mismatch. Expected $payloadLength, remaining ${buffer.remaining()}")
            }

            val payload = ByteArray(payloadLength)
            if (payloadLength > 0) {
                buffer.get(payload)
            }

            return BlePacket(
                version = version,
                type = BlePacketType.fromValue(typeValue),
                ttl = ttl,
                flags = flags,
                transferId = transferId,
                chunkIndex = chunkIndex,
                totalChunks = totalChunks,
                payloadLength = payloadLength,
                messageId = messageId,
                sourceId = sourceId,
                destId = destId,
                senderId = senderId,
                payload = payload
            )
        }
    }
}
