package com.example.flutter_app

import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import com.example.flutter_app.protocol.BlePacket
import com.example.flutter_app.protocol.BlePacketCodec
import com.example.flutter_app.protocol.BlePacketType
import com.example.flutter_app.protocol.BlePacketValidator
import com.example.flutter_app.protocol.BleReassemblyBuffer
import com.example.flutter_app.protocol.BleMessage
import org.json.JSONObject
import kotlin.random.Random

class BleMessagingManager(private val context: Context) {
    companion object {
        const val TAG = "OfflineMeshBLEMsg"
        // Stable UUIDs
        val SERVICE_UUID: UUID = UUID.fromString("00001103-0000-1000-8000-00805F9B34FB")
        val RX_CHAR_UUID: UUID = UUID.fromString("00001104-0000-1000-8000-00805F9B34FB") // Client -> Server (Write)
        val TX_CHAR_UUID: UUID = UUID.fromString("00001105-0000-1000-8000-00805F9B34FB") // Server -> Client (Notify)

        // Descriptor for Notifications
        val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")

        const val DEFAULT_MTU = 20
        const val MAX_MTU = 512
    }

    private val bluetoothManager: BluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    // Server-side
    private var gattServer: BluetoothGattServer? = null
    private val serverConnections = ConcurrentHashMap<String, BluetoothDevice>()

    // Client-side
    private val gattClients = ConcurrentHashMap<String, BluetoothGatt>()

    // MTU tracking per address
    private val deviceMtu = ConcurrentHashMap<String, Int>()

    // Local Identity
    private var localId: String = ""
    private var forwardingService: BleForwardingService? = null
    private var routingService: BleRoutingService? = null
    private var storeAndForwardService: BleStoreAndForwardService? = null

    // Reassembly buffers per device address
    private val reassemblyBuffers = ConcurrentHashMap<String, BleReassemblyBuffer>()

    fun setupChannels(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    localId = call.argument<String>("localId") ?: ""
                    
                    if (routingService == null && localId.isNotEmpty()) {
                        routingService = BleRoutingService(localId)
                    }
                    if (forwardingService == null && localId.isNotEmpty()) {
                        forwardingService = BleForwardingService(
                            localId = localId,
                            onDeliverToFlutter = { msg ->
                                val fullMessage = String(msg.payload, Charsets.UTF_8)
                                sendEvent(mapOf("type" to "message", "address" to "mesh", "message" to fullMessage))
                            },
                            onForwardToMesh = { msg ->
                                forwardMessageToMesh(msg)
                            },
                            onAckReceived = { ackedId ->
                                storeAndForwardService?.onAckReceived(ackedId)
                            }
                        )
                    }
                    if (storeAndForwardService == null && localId.isNotEmpty()) {
                        storeAndForwardService = BleStoreAndForwardService(context.filesDir) { msg ->
                            forwardMessageToMesh(msg)
                        }
                    }

                    startServer()
                    result.success(null)
                }
                "stopServer" -> {
                    stopServer()
                    result.success(null)
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        connectToDevice(address)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Address is null", null)
                    }
                }
                "disconnect" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        disconnectDevice(address)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Address is null", null)
                    }
                }
                "sendMessage" -> {
                    val address = call.argument<String>("address")
                    val message = call.argument<String>("message")
                    if (address != null && message != null) {
                        executor.submit { sendMessage(address, message) }
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Address or message is null", null)
                    }
                }
                "hasRoute" -> {
                    val destId = call.argument<String>("destId")
                    if (destId != null) {
                        val hasRoute = routingService?.getNextHop(destId) != null
                        result.success(hasRoute)
                    } else {
                        result.error("INVALID_ARG", "destId is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                stopServer()
                gattClients.values.forEach { it.disconnect() }
            }
        })
    }

    // =========================================================================
    // GATT SERVER LOGIC
    // =========================================================================

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            val address = device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Server: Connected to $address")
                serverConnections[address] = device
                deviceMtu[address] = DEFAULT_MTU // Reset MTU
                sendEvent(mapOf("type" to "connected", "address" to address, "isIncoming" to true))
                updateRetryTimerState()
                sendRoutingTableTo(address)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Server: Disconnected from $address")
                serverConnections.remove(address)
                deviceMtu.remove(address)
                sendEvent(mapOf("type" to "disconnected", "address" to address))
                handleDisconnectRouting(address)
                updateRetryTimerState()
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
            if (characteristic.uuid == RX_CHAR_UUID) {
                handleIncomingChunk(device.address, value)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
            if (descriptor.uuid == CLIENT_CHARACTERISTIC_CONFIG_UUID) {
                Log.d(TAG, "Server: Client enabled notifications for ${device.address}")
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            super.onMtuChanged(device, mtu)
            Log.d(TAG, "Server: MTU changed to $mtu for ${device.address}")
            deviceMtu[device.address] = mtu
        }
    }

    private fun startServer() {
        if (gattServer != null) return
        try {
            gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

            val rxChar = BluetoothGattCharacteristic(
                RX_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            val txChar = BluetoothGattCharacteristic(
                TX_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            val cccDescriptor = BluetoothGattDescriptor(
                CLIENT_CHARACTERISTIC_CONFIG_UUID,
                BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ
            )
            txChar.addDescriptor(cccDescriptor)

            service.addCharacteristic(rxChar)
            service.addCharacteristic(txChar)

            gattServer?.addService(service)
            Log.d(TAG, "GATT Server started")
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing permission to start GATT server")
        }
    }

    private fun stopServer() {
        try {
            gattServer?.clearServices()
            gattServer?.close()
            gattServer = null
            serverConnections.clear()
        } catch (e: SecurityException) {
            // Ignore
        }
    }

    // =========================================================================
    // GATT CLIENT LOGIC
    // =========================================================================

    private val gattClientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            super.onConnectionStateChange(gatt, status, newState)
            val address = gatt.device.address
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Client: Connected to $address. Requesting MTU...")
                gattClients[address] = gatt
                deviceMtu[address] = DEFAULT_MTU
                sendEvent(mapOf("type" to "connected", "address" to address, "isIncoming" to false))
                updateRetryTimerState()
                
                try {
                    // Request highest possible MTU
                    gatt.requestMtu(MAX_MTU)
                } catch (e: SecurityException) {
                    gatt.discoverServices()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Client: Disconnected from $address")
                gattClients.remove(address)
                deviceMtu.remove(address)
                gatt.close()
                sendEvent(mapOf("type" to "disconnected", "address" to address))
                handleDisconnectRouting(address)
                updateRetryTimerState()
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            super.onMtuChanged(gatt, mtu, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "Client: MTU changed to $mtu for ${gatt.device.address}")
                deviceMtu[gatt.device.address] = mtu
            }
            try {
                gatt.discoverServices()
            } catch (e: SecurityException) { }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            super.onServicesDiscovered(gatt, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt.getService(SERVICE_UUID)
                if (service != null) {
                    val txChar = service.getCharacteristic(TX_CHAR_UUID)
                    if (txChar != null) {
                        try {
                            gatt.setCharacteristicNotification(txChar, true)
                            val descriptor = txChar.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
                            if (descriptor != null) {
                                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                                gatt.writeDescriptor(descriptor)
                            }
                        } catch (e: SecurityException) { }
                    }
                    sendRoutingTableTo(gatt.device.address)
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            super.onCharacteristicChanged(gatt, characteristic)
            if (characteristic.uuid == TX_CHAR_UUID) {
                handleIncomingChunk(gatt.device.address, characteristic.value)
            }
        }
    }

    private fun connectToDevice(address: String) {
        if (gattClients.containsKey(address) || serverConnections.containsKey(address)) {
            Log.d(TAG, "Already connected to $address")
            return
        }
        val device = bluetoothAdapter?.getRemoteDevice(address)
        if (device != null) {
            try {
                device.connectGatt(context, false, gattClientCallback, BluetoothDevice.TRANSPORT_LE)
            } catch (e: SecurityException) {
                Log.e(TAG, "Permission denied for connectGatt")
            }
        }
    }

    private fun disconnectDevice(address: String) {
        try {
            gattClients[address]?.disconnect()
            gattClients[address]?.close()
            gattClients.remove(address)
            
            // Note: Android does not provide a direct way to forcefully disconnect a remote device from our GATT server,
            // we just rely on them closing, or we can just remove them from our maps.
            serverConnections.remove(address)
            
        } catch (e: SecurityException) { }
    }

    private fun handleDisconnectRouting(macAddress: String) {
        val routing = routingService ?: return
        val invalidated = routing.removeRoutesForMac(macAddress)
        if (invalidated.isNotEmpty()) {
            val poisonBytes = routing.getPoisonReverseBytes(invalidated)
            if (poisonBytes.isNotEmpty()) {
                broadcastRoutingTable(poisonBytes)
            }
        }
    }

    private fun updateRetryTimerState() {
        val hasConnections = gattClients.isNotEmpty() || serverConnections.isNotEmpty()
        if (hasConnections) {
            storeAndForwardService?.startRetryTimer()
        } else {
            storeAndForwardService?.stopRetryTimer()
        }
    }

    private fun sendRoutingTableTo(address: String) {
        val routing = routingService ?: return
        val bytes = routing.getRoutingTableBytes()
        if (bytes.isNotEmpty()) {
            val transferId = Random.nextInt()
            sendRawBytesAsPacket(address, bytes, BlePacketType.ROUTE_ADVERT, transferId)
        }
    }

    private fun broadcastRoutingTable(bytes: ByteArray) {
        val allAddresses = gattClients.keys + serverConnections.keys
        for (address in allAddresses) {
            val transferId = Random.nextInt()
            sendRawBytesAsPacket(address, bytes, BlePacketType.ROUTE_ADVERT, transferId)
        }
    }

    private fun forwardMessageToMesh(bleMessage: BleMessage) {
        // Step 20 Unicast Routing: instead of broadcasting, check routing table
        val destId = bleMessage.destId
        if (destId.isNotEmpty()) {
            val nextHop = routingService?.getNextHop(destId)
            if (nextHop != null) {
                Log.d(TAG, "Forwarding to next hop $nextHop for destination $destId")
                sendToAddress(nextHop, bleMessage, Random.nextInt())
                return
            } else {
                Log.d(TAG, "No route found for destination $destId. Queueing for store-and-forward.")
                storeAndForwardService?.queueMessage(bleMessage)
                return
            }
        }
        
        // Fallback for broadcast/unknown (e.g. if destId is somehow empty)
        val transferId = Random.nextInt()
        val allAddresses = gattClients.keys + serverConnections.keys
        for (address in allAddresses) {
            sendToAddress(address, bleMessage, transferId)
        }
    }

    private fun sendMessage(address: String, message: String) {
        val payloadBytes = message.toByteArray(Charsets.UTF_8)
        val transferId = Random.nextInt()
        
        // Parse metadata
        var messageId = ""
        var sourceId = localId
        var destId = ""
        try {
            val json = JSONObject(message)
            messageId = json.optString("id", UUID.randomUUID().toString())
            sourceId = json.optString("senderId", localId)
            destId = json.optString("recipientId", "")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse JSON for routing")
        }

        val bleMessage = BleMessage(
            type = BlePacketType.MESSAGE,
            messageId = messageId,
            sourceId = sourceId,
            destId = destId,
            senderId = localId,
            ttl = BleForwardingService.MAX_TTL,
            payload = payloadBytes
        )
        
        // Mark as seen so we don't reflect our own outgoing message
        forwardingService?.markAsSeen(messageId)

        // If the Flutter layer requested "mesh", we must resolve it via routing
        if (address == "mesh") {
            val nextHop = routingService?.getNextHop(destId)
            if (nextHop != null) {
                Log.d(TAG, "Routing message for $destId to next hop $nextHop")
                sendToAddress(nextHop, bleMessage, transferId)
            } else {
                Log.d(TAG, "No BLE route found for destination $destId. Queueing for store-and-forward.")
                storeAndForwardService?.queueMessage(bleMessage)
            }
        } else {
            sendToAddress(address, bleMessage, transferId)
        }
    }
    
    private fun sendToAddress(address: String, bleMessage: BleMessage, transferId: Int) {
        val currentMtu = deviceMtu[address] ?: DEFAULT_MTU
        val payloadBytes = bleMessage.payload
        
        // chunk 0 requires extra space for IDs
        val routingLen = 4 + bleMessage.messageId.toByteArray().size + 
                         bleMessage.sourceId.toByteArray().size + 
                         bleMessage.destId.toByteArray().size + 
                         bleMessage.senderId.toByteArray().size
                         
        val chunk0Capacity = (currentMtu - 3 - BlePacket.BASE_HEADER_SIZE - routingLen).coerceAtLeast(1)
        val chunkNCapacity = (currentMtu - 3 - BlePacket.BASE_HEADER_SIZE).coerceAtLeast(1)
        
        var totalChunks = 1
        if (payloadBytes.size > chunk0Capacity) {
            val remaining = payloadBytes.size - chunk0Capacity
            val additionalChunks = Math.ceil(remaining.toDouble() / chunkNCapacity).toInt()
            totalChunks = 1 + additionalChunks
        }

        if (totalChunks > BlePacketValidator.MAX_CHUNKS) {
            Log.e(TAG, "Message too large to send over BLE to $address")
            return
        }

        var offset = 0
        for (i in 0 until totalChunks) {
            val capacity = if (i == 0) chunk0Capacity else chunkNCapacity
            val end = Math.min(offset + capacity, payloadBytes.size)
            val chunkBytes = payloadBytes.copyOfRange(offset, end)
            
            val packet = BlePacket(
                type = BlePacketType.MESSAGE,
                ttl = bleMessage.ttl,
                transferId = transferId,
                chunkIndex = i,
                totalChunks = totalChunks,
                payloadLength = chunkBytes.size,
                messageId = if (i == 0) bleMessage.messageId else "",
                sourceId = if (i == 0) bleMessage.sourceId else "",
                destId = if (i == 0) bleMessage.destId else "",
                senderId = if (i == 0) bleMessage.senderId else "",
                payload = chunkBytes
            )
            
            val encodedBytes = BlePacketCodec.encode(packet)
            sendPacket(address, encodedBytes)
            
            offset += capacity
            // Brief sleep to avoid overflowing BLE hardware buffers
            Thread.sleep(10)
        }
    }

    private fun sendRawBytesAsPacket(address: String, payloadBytes: ByteArray, type: BlePacketType, transferId: Int) {
        val currentMtu = deviceMtu[address] ?: DEFAULT_MTU
        val chunkCapacity = (currentMtu - 3 - BlePacket.BASE_HEADER_SIZE).coerceAtLeast(1)
        
        var totalChunks = 1
        if (payloadBytes.size > chunkCapacity) {
            val remaining = payloadBytes.size - chunkCapacity
            val additionalChunks = Math.ceil(remaining.toDouble() / chunkCapacity).toInt()
            totalChunks = 1 + additionalChunks
        }

        if (totalChunks > BlePacketValidator.MAX_CHUNKS) {
            Log.e(TAG, "Raw packet too large to send over BLE to $address")
            return
        }

        var offset = 0
        for (i in 0 until totalChunks) {
            val end = Math.min(offset + chunkCapacity, payloadBytes.size)
            val chunkBytes = payloadBytes.copyOfRange(offset, end)
            
            val packet = BlePacket(
                type = type,
                ttl = BleForwardingService.MAX_TTL,
                transferId = transferId,
                chunkIndex = i,
                totalChunks = totalChunks,
                payloadLength = chunkBytes.size,
                messageId = "",
                sourceId = "",
                destId = "",
                senderId = "",
                payload = chunkBytes
            )
            
            val encodedBytes = BlePacketCodec.encode(packet)
            sendPacket(address, encodedBytes)
            
            offset += chunkCapacity
            Thread.sleep(10)
        }
    }

    private fun sendPacket(address: String, packet: ByteArray) {
        try {
            // If we are connected as a client, write to their RX char
            val gatt = gattClients[address]
            if (gatt != null) {
                val service = gatt.getService(SERVICE_UUID)
                val rxChar = service?.getCharacteristic(RX_CHAR_UUID)
                if (rxChar != null) {
                    rxChar.value = packet
                    gatt.writeCharacteristic(rxChar)
                }
                return
            }

            // If they are connected to us as a peripheral, notify their TX char
            val device = serverConnections[address]
            val server = gattServer
            if (device != null && server != null) {
                val service = server.getService(SERVICE_UUID)
                val txChar = service?.getCharacteristic(TX_CHAR_UUID)
                if (txChar != null) {
                    txChar.value = packet
                    server.notifyCharacteristicChanged(device, txChar, false)
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission error sending packet", e)
        }
    }

    private fun handleIncomingChunk(address: String, data: ByteArray) {
        try {
            val packet = BlePacketCodec.decode(data)
            if (!BlePacketValidator.validate(packet)) {
                Log.e(TAG, "Invalid packet received from $address")
                return
            }
            val buffer = getReassemblyBuffer(address)
            buffer.processPacket(packet)
        } catch (e: Exception) {
            Log.e(TAG, "Error handling incoming chunk from $address: ${e.message}")
        }
    }
    
    private fun getReassemblyBuffer(address: String): BleReassemblyBuffer {
        return reassemblyBuffers.getOrPut(address) {
            BleReassemblyBuffer().apply {
                onMessageComplete = { bleMessage ->
                    if (bleMessage.type == BlePacketType.ROUTE_ADVERT) {
                        Log.d(TAG, "Received ROUTE_ADVERT from $address")
                        val changedRoutes = routingService?.processRoutingTableBytes(bleMessage.payload, address) ?: emptySet()
                        if (changedRoutes.isNotEmpty()) {
                            // Flush any queued messages for the newly discovered routes
                            changedRoutes.forEach { destId ->
                                storeAndForwardService?.onRouteAvailable(destId)
                            }
                            // Propagate our updated routing table
                            val newBytes = routingService?.getRoutingTableBytes()
                            if (newBytes != null && newBytes.isNotEmpty()) {
                                broadcastRoutingTable(newBytes)
                            }
                        }
                    } else {
                        forwardingService?.processMessage(bleMessage)
                    }
                }
            }
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }
}
