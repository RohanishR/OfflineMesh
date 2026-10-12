package com.example.flutter_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

class BluetoothFileTransferManager(private val context: Context) {
    companion object {
        const val TAG = "OfflineMeshBTFile"
        // A distinct UUID exclusively for OfflineMesh Bluetooth File Transfer
        val OFFLINEMESH_FILE_UUID: UUID = UUID.fromString("00001102-0000-1000-8000-00805F9B34FB")
    }

    private var serverThread: ServerThread? = null
    
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
                "sendFile" -> {
                    val address = call.argument<String>("address")
                    val metadataJson = call.argument<String>("metadata")
                    val filePath = call.argument<String>("filePath")
                    
                    if (address != null && metadataJson != null && filePath != null) {
                        sendFile(address, metadataJson, filePath)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "Missing parameters", null)
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
    }

    private fun sendFile(address: String, metadataJson: String, filePath: String) {
        thread {
            var socket: BluetoothSocket? = null
            try {
                val device = bluetoothAdapter?.getRemoteDevice(address) ?: return@thread
                socket = device.createRfcommSocketToServiceRecord(OFFLINEMESH_FILE_UUID)
                socket.connect()

                val outStream = socket.outputStream
                
                // 1. Send metadata JSON + newline delimiter
                val header = "$metadataJson\n"
                outStream.write(header.toByteArray(Charsets.UTF_8))
                outStream.flush()
                
                // 2. Stream file bytes
                val file = File(filePath)
                val fileSize = file.length().toDouble()
                var sentBytes = 0L
                val buffer = ByteArray(8192)
                
                FileInputStream(file).use { fis ->
                    var bytesRead: Int
                    while (fis.read(buffer).also { bytesRead = it } != -1) {
                        outStream.write(buffer, 0, bytesRead)
                        sentBytes += bytesRead
                        
                        // Report progress sparingly (e.g. every ~64KB)
                        if (fileSize > 0 && sentBytes % (8192 * 8) == 0L) {
                            sendEvent(mapOf(
                                "type" to "progress",
                                "address" to address,
                                "progress" to (sentBytes / fileSize)
                            ))
                        }
                    }
                }
                outStream.flush()
                
                sendEvent(mapOf("type" to "sent", "address" to address))
            } catch (e: Exception) {
                Log.e(TAG, "File send failed to $address", e)
                sendEvent(mapOf("type" to "error", "address" to address, "error" to e.message))
            } finally {
                try { socket?.close() } catch (e: Exception) {}
            }
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private inner class ServerThread : Thread() {
        private val serverSocket: BluetoothServerSocket? by lazy(LazyThreadSafetyMode.NONE) {
            try {
                bluetoothAdapter?.listenUsingRfcommWithServiceRecord("OfflineMeshFile", OFFLINEMESH_FILE_UUID)
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
                    thread { handleIncomingFile(it, address) }
                }
            }
        }

        private fun handleIncomingFile(socket: BluetoothSocket, address: String) {
            var tempFile: File? = null
            try {
                val inStream: InputStream = socket.inputStream
                val buffer = ByteArray(8192)
                var bytesRead: Int
                
                // Read header until newline
                val headerBuilder = java.lang.StringBuilder()
                var newlineFound = false
                var byteInt: Int
                
                while (inStream.read().also { byteInt = it } != -1) {
                    val c = byteInt.toChar()
                    if (c == '\n') {
                        newlineFound = true
                        break
                    }
                    headerBuilder.append(c)
                }
                
                if (!newlineFound) {
                    Log.w(TAG, "Incoming connection closed before metadata newline.")
                    return
                }
                
                val metadataJson = headerBuilder.toString()
                
                // Open temp file in app cache dir
                tempFile = File(context.cacheDir, "bt_file_${UUID.randomUUID()}")
                
                val digest = MessageDigest.getInstance("SHA-256")
                
                FileOutputStream(tempFile).use { fos ->
                    while (inStream.read(buffer).also { bytesRead = it } != -1) {
                        fos.write(buffer, 0, bytesRead)
                        digest.update(buffer, 0, bytesRead)
                    }
                }
                
                // Checksum logic will be verified on Dart side since we pass the file path.
                // Wait, it's safer/faster to pass the calculated checksum back to Dart.
                val hashBytes = digest.digest()
                val calculatedHash = hashBytes.joinToString("") { "%02x".format(it) }
                
                sendEvent(mapOf(
                    "type" to "incoming_file",
                    "address" to address,
                    "metadata" to metadataJson,
                    "tempFilePath" to tempFile.absolutePath,
                    "calculatedHash" to calculatedHash
                ))
                
            } catch (e: Exception) {
                Log.e(TAG, "Error receiving file from $address", e)
                tempFile?.delete()
                sendEvent(mapOf("type" to "error", "address" to address, "error" to e.message))
            } finally {
                try { socket.close() } catch (e: Exception) {}
            }
        }

        fun cancel() {
            try {
                serverSocket?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Could not close server socket", e)
            }
        }
    }
}
