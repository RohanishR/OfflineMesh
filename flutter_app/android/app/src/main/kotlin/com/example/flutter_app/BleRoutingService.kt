package com.example.flutter_app

import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap

data class RouteEntry(
    val destId: String,
    val nextHopMac: String,
    val hopCount: Int,
    val timestamp: Long
)

class BleRoutingService(private val localId: String) {
    companion object {
        const val TAG = "BleRouting"
        const val MAX_HOPS = 10
        const val INF_HOPS = 255
    }

    // destId -> RouteEntry
    private val routingTable = ConcurrentHashMap<String, RouteEntry>()

    fun getNextHop(destId: String): String? {
        val entry = routingTable[destId]
        return if (entry != null && entry.hopCount < MAX_HOPS) entry.nextHopMac else null
    }

    fun hasRoute(destId: String): Boolean {
        return getNextHop(destId) != null
    }

    /**
     * Updates the routing table with a route advertised by 'senderMac'.
     * Returns true if the routing table was changed (meaning we should broadcast updates).
     */
    fun updateRoute(destId: String, senderMac: String, advertisedHops: Int): Boolean {
        if (destId == localId) return false // Don't route to ourselves
        if (destId.isEmpty()) return false

        val newHopCount = if (advertisedHops == INF_HOPS) INF_HOPS else advertisedHops + 1

        val currentEntry = routingTable[destId]

        if (currentEntry == null) {
            if (newHopCount < MAX_HOPS) {
                routingTable[destId] = RouteEntry(destId, senderMac, newHopCount, System.currentTimeMillis())
                Log.d(TAG, "Added new route: $destId via $senderMac (hops: $newHopCount)")
                return true
            }
        } else {
            // If the route is via the same next hop, always update (could be cost increase or decrease)
            if (currentEntry.nextHopMac == senderMac) {
                if (currentEntry.hopCount != newHopCount) {
                    routingTable[destId] = RouteEntry(destId, senderMac, newHopCount, System.currentTimeMillis())
                    Log.d(TAG, "Updated existing route: $destId via $senderMac (new hops: $newHopCount)")
                    return true
                } else {
                    // Just refresh timestamp
                    routingTable[destId] = currentEntry.copy(timestamp = System.currentTimeMillis())
                    return false
                }
            } else {
                // If via a different hop, only update if strictly better
                if (newHopCount < currentEntry.hopCount) {
                    routingTable[destId] = RouteEntry(destId, senderMac, newHopCount, System.currentTimeMillis())
                    Log.d(TAG, "Found better route: $destId via $senderMac (hops: $newHopCount)")
                    return true
                }
            }
        }
        return false
    }

    /**
     * Removes all routes that were using the given MAC address as next hop.
     * Returns a list of destIds that were invalidated so they can be broadcasted as INF_HOPS (poison reverse).
     */
    fun removeRoutesForMac(macAddress: String): List<String> {
        val invalidated = mutableListOf<String>()
        val iterator = routingTable.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.value.nextHopMac == macAddress) {
                invalidated.add(entry.key)
                iterator.remove()
                Log.d(TAG, "Removed route: ${entry.key} because next hop $macAddress disconnected")
            }
        }
        return invalidated
    }

    /**
     * Serializes the current routing table (plus localId) into a byte array for ROUTE_ADVERT.
     * Format: [1 byte numRoutes]
     * For each route: [1 byte destId len][destId bytes][1 byte hopCount]
     */
    fun getRoutingTableBytes(): ByteArray {
        val routesToShare = routingTable.values.filter { it.hopCount < MAX_HOPS }
        // +1 for localId
        val numEntries = Math.min(routesToShare.size + 1, 255) 

        var totalSize = 1 // numRoutes
        val localBytes = localId.toByteArray(Charsets.UTF_8)
        totalSize += 1 + localBytes.size + 1 // localId entry

        val entriesToEncode = routesToShare.take(numEntries - 1).map {
            val bytes = it.destId.toByteArray(Charsets.UTF_8)
            Pair(bytes, it.hopCount)
        }

        for (entry in entriesToEncode) {
            totalSize += 1 + entry.first.size + 1
        }

        val buffer = ByteBuffer.allocate(totalSize)
        buffer.order(ByteOrder.BIG_ENDIAN)
        buffer.put(numEntries.toByte())

        // Add self
        buffer.put(localBytes.size.toByte())
        buffer.put(localBytes)
        buffer.put(0.toByte()) // 0 hops to self

        // Add other routes
        for (entry in entriesToEncode) {
            buffer.put(entry.first.size.toByte())
            buffer.put(entry.first)
            buffer.put(entry.second.toByte())
        }

        return buffer.array()
    }

    /**
     * Serializes specific invalidated routes into a byte array for poison reverse.
     */
    fun getPoisonReverseBytes(invalidatedDestIds: List<String>): ByteArray {
        val numEntries = Math.min(invalidatedDestIds.size, 255)
        if (numEntries == 0) return ByteArray(0)

        var totalSize = 1 // numRoutes
        val entriesToEncode = invalidatedDestIds.take(numEntries).map { it.toByteArray(Charsets.UTF_8) }

        for (bytes in entriesToEncode) {
            totalSize += 1 + bytes.size + 1
        }

        val buffer = ByteBuffer.allocate(totalSize)
        buffer.order(ByteOrder.BIG_ENDIAN)
        buffer.put(numEntries.toByte())

        for (bytes in entriesToEncode) {
            buffer.put(bytes.size.toByte())
            buffer.put(bytes)
            buffer.put(INF_HOPS.toByte()) // infinity
        }

        return buffer.array()
    }

    /**
     * Parses a ROUTE_ADVERT payload and updates the routing table.
     * Returns true if the routing table changed.
     */
    fun processRoutingTableBytes(payload: ByteArray, senderMac: String): Set<String> {
        val changedRoutes = mutableSetOf<String>()
        if (payload.isEmpty()) return changedRoutes
        val buffer = ByteBuffer.wrap(payload)
        buffer.order(ByteOrder.BIG_ENDIAN)

        if (buffer.remaining() < 1) return changedRoutes
        val numEntries = buffer.get().toInt() and 0xFF

        for (i in 0 until numEntries) {
            if (buffer.remaining() < 1) break
            val len = buffer.get().toInt() and 0xFF
            if (buffer.remaining() < len) break
            val destBytes = ByteArray(len)
            buffer.get(destBytes)
            val destId = String(destBytes, Charsets.UTF_8)
            
            if (buffer.remaining() < 1) break
            val hops = buffer.get().toInt() and 0xFF

            if (updateRoute(destId, senderMac, hops)) {
                changedRoutes.add(destId)
            }
        }
        return changedRoutes
    }
}
