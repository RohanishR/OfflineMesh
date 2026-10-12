package com.example.flutter_app

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer

class BleRoutingServiceTest {

    @Test
    fun testAddAndRetrieveRoute() {
        val service = BleRoutingService("A")
        
        // B connects and advertises it is B (hops 0)
        val changed = service.updateRoute("B", "mac_B", 0)
        assertTrue("Should add new route", changed)
        
        assertEquals("Next hop should be B's MAC", "mac_B", service.getNextHop("B"))
        assertTrue(service.hasRoute("B"))
    }

    @Test
    fun testUpdateWithBetterRoute() {
        val service = BleRoutingService("A")
        
        // Route to C via B (cost 3: B advertised 2 hops to C)
        service.updateRoute("C", "mac_B", 2)
        assertEquals("mac_B", service.getNextHop("C"))
        
        // Later D connects and advertises it is 0 hops to C (so C is 1 hop from us)
        val changed = service.updateRoute("C", "mac_D", 0)
        assertTrue("Should update route to a shorter path", changed)
        assertEquals("Next hop should be updated to D's MAC", "mac_D", service.getNextHop("C"))
    }
    
    @Test
    fun testIgnoreWorseRoute() {
        val service = BleRoutingService("A")
        
        // Route to C via D (cost 1)
        service.updateRoute("C", "mac_D", 0)
        
        // B advertises route to C (cost 3)
        val changed = service.updateRoute("C", "mac_B", 2)
        assertFalse("Should not update to a worse route", changed)
        assertEquals("Next hop should remain D's MAC", "mac_D", service.getNextHop("C"))
    }
    
    @Test
    fun testUpdateSameNextHop() {
        val service = BleRoutingService("A")
        
        service.updateRoute("C", "mac_B", 2)
        
        // B's path to C gets longer
        val changed = service.updateRoute("C", "mac_B", 4)
        assertTrue("Should update route if the same next hop advertises a different cost", changed)
    }

    @Test
    fun testRemoveRoutesForMac() {
        val service = BleRoutingService("A")
        
        service.updateRoute("B", "mac_B", 0)
        service.updateRoute("C", "mac_B", 1)
        service.updateRoute("D", "mac_D", 0)
        
        val invalidated = service.removeRoutesForMac("mac_B")
        
        assertEquals(2, invalidated.size)
        assertTrue(invalidated.contains("B"))
        assertTrue(invalidated.contains("C"))
        
        assertNull(service.getNextHop("B"))
        assertNull(service.getNextHop("C"))
        assertEquals("mac_D", service.getNextHop("D"))
    }

    @Test
    fun testRoutingTableSerialization() {
        val service = BleRoutingService("A")
        service.updateRoute("B", "mac_B", 0)
        service.updateRoute("C", "mac_B", 1)
        
        val bytes = service.getRoutingTableBytes()
        
        // Manually decode to verify
        val buffer = ByteBuffer.wrap(bytes)
        val numEntries = buffer.get().toInt()
        assertEquals(3, numEntries) // A, B, C
        
        var foundA = false
        var foundB = false
        var foundC = false
        
        for (i in 0 until numEntries) {
            val len = buffer.get().toInt()
            val destBytes = ByteArray(len)
            buffer.get(destBytes)
            val destId = String(destBytes, Charsets.UTF_8)
            val hops = buffer.get().toInt()
            
            when (destId) {
                "A" -> {
                    assertEquals(0, hops)
                    foundA = true
                }
                "B" -> {
                    assertEquals(1, hops) // B advertised 0, we stored 1
                    foundB = true
                }
                "C" -> {
                    assertEquals(2, hops) // B advertised 1, we stored 2
                    foundC = true
                }
            }
        }
        
        assertTrue(foundA && foundB && foundC)
    }
    
    @Test
    fun testParseRoutingTable() {
        val sender = BleRoutingService("B")
        // B's local ID
        
        val receiver = BleRoutingService("A")
        val changed = receiver.processRoutingTableBytes(sender.getRoutingTableBytes(), "mac_B")
        
        assertTrue(changed.isNotEmpty())
        assertTrue(receiver.hasRoute("B"))
        assertEquals("mac_B", receiver.getNextHop("B"))
    }
}
