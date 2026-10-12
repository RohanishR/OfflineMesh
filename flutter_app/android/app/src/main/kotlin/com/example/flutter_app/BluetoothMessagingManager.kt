package com.example.flutter_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

class BluetoothMessagingManager {
    companion object {
        const val TAG = "OfflineMeshBluetooth"
        // A well-known UUID for OfflineMesh Bluetooth Classic SPP
        val OFFLINEMESH_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB") // Standard SPP UUID
    }

    private var serverThread: ServerThread? = null
    private val connectedThreads = ConcurrentHashMap<String, ConnectedThread>()
    
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    fun setupChannels(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
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
                "sendMessage" -> {
                    val address = call.argument<String>("address")
                    val message = call.argument<String>("message")
                    if (address != null && message != null) {
                        sendMessage(address, message)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Address or message is null", null)
                    }
                }
                "disconnect" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        disconnect(address)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Address is null", null)
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
            }
        })
    }

    private fun startServer() {
        if (bluetoothAdapter == null) return
        if (serverThread != null) return
        serverThread = ServerThread().apply { start() }
    }

    private fun stopServer() {
        serverThread?.cancel()
        serverThread = null
        connectedThreads.values.forEach { it.cancel() }
        connectedThreads.clear()
    }

    private fun connectToDevice(address: String) {
        if (bluetoothAdapter == null) return
        if (connectedThreads.containsKey(address)) return

        thread {
            try {
                val device = bluetoothAdapter.getRemoteDevice(address)
                val socket = device.createRfcommSocketToServiceRecord(OFFLINEMESH_UUID)
                socket.connect()
                
                manageConnectedSocket(socket, address, isIncoming = false)
            } catch (e: Exception) {
                Log.e(TAG, "Connection failed to $address", e)
                sendEvent(mapOf("type" to "error", "address" to address, "error" to e.message))
            }
        }
    }

    private fun manageConnectedSocket(socket: BluetoothSocket, address: String, isIncoming: Boolean) {
        val thread = ConnectedThread(socket, address)
        connectedThreads[address] = thread
        thread.start()
        
        sendEvent(mapOf("type" to "connected", "address" to address, "isIncoming" to isIncoming))
    }

    private fun sendMessage(address: String, message: String) {
        val thread = connectedThreads[address]
        if (thread != null) {
            // Append newline for framing
            thread.write((message + "\n").toByteArray(Charsets.UTF_8))
        } else {
            Log.w(TAG, "Cannot send message, no connection to $address")
        }
    }

    private fun disconnect(address: String) {
        connectedThreads[address]?.cancel()
        connectedThreads.remove(address)
        sendEvent(mapOf("type" to "disconnected", "address" to address))
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private inner class ServerThread : Thread() {
        private val serverSocket: BluetoothServerSocket? by lazy(LazyThreadSafetyMode.NONE) {
            try {
                bluetoothAdapter?.listenUsingRfcommWithServiceRecord("OfflineMesh", OFFLINEMESH_UUID)
            } catch (e: SecurityException) {
                null
            }
        }

        override fun run() {
            var shouldLoop = true
            while (shouldLoop) {
                val socket: BluetoothSocket? = try {
                    serverSocket?.accept()
                } catch (e: Exception) {
                    shouldLoop = false
                    null
                }
                
                socket?.also {
                    val address = it.remoteDevice.address
                    if (!connectedThreads.containsKey(address)) {
                        manageConnectedSocket(it, address, isIncoming = true)
                    } else {
                        // Already connected, close this duplicate
                        try { it.close() } catch (e: Exception) {}
                    }
                }
            }
        }

        fun cancel() {
            try {
                serverSocket?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Could not close the connect socket", e)
            }
        }
    }

    private inner class ConnectedThread(private val socket: BluetoothSocket, private val address: String) : Thread() {
        private val inStream: InputStream = socket.inputStream
        private val outStream: OutputStream = socket.outputStream

        override fun run() {
            val buffer = ByteArray(4096)
            var bytes: Int
            val messageBuilder = StringBuilder()

            while (true) {
                try {
                    bytes = inStream.read(buffer)
                    val chunk = String(buffer, 0, bytes, Charsets.UTF_8)
                    messageBuilder.append(chunk)

                    // Process complete messages separated by newline
                    var newlineIndex = messageBuilder.indexOf("\n")
                    while (newlineIndex != -1) {
                        val message = messageBuilder.substring(0, newlineIndex)
                        messageBuilder.delete(0, newlineIndex + 1)
                        
                        // Emit message to Flutter
                        sendEvent(mapOf("type" to "message", "address" to address, "message" to message))
                        
                        newlineIndex = messageBuilder.indexOf("\n")
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Input stream disconnected", e)
                    disconnect(address)
                    break
                }
            }
        }

        fun write(bytes: ByteArray) {
            try {
                outStream.write(bytes)
                outStream.flush()
            } catch (e: Exception) {
                Log.e(TAG, "Error occurred when sending data", e)
                disconnect(address)
            }
        }

        fun cancel() {
            try {
                socket.close()
            } catch (e: Exception) {
                Log.e(TAG, "Could not close the connect socket", e)
            }
        }
    }
}
