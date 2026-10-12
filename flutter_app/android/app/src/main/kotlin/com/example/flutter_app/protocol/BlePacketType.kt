package com.example.flutter_app.protocol

enum class BlePacketType(val value: Byte) {
    UNKNOWN(0),
    MESSAGE(1),
    HANDSHAKE(2),
    ACK(3),
    ROUTE_ADVERT(4);

    companion object {
        fun fromValue(value: Byte): BlePacketType {
            return values().find { it.value == value } ?: UNKNOWN
        }
    }
}
