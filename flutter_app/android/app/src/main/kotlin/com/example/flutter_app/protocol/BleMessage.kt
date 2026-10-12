package com.example.flutter_app.protocol

data class BleMessage(
    val type: BlePacketType,
    val messageId: String,
    val sourceId: String,
    val destId: String,
    val senderId: String, // Identity of the device that just relayed this to us
    val ttl: Byte,
    val payload: ByteArray
)
