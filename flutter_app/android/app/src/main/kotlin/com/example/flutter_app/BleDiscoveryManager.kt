package com.example.flutter_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class BleDiscoveryManager(private val context: Context) {
    companion object {
        const val TAG = "OfflineMeshBLE"
        // Stable OfflineMesh BLE Service UUID
        val OFFLINEMESH_BLE_UUID: UUID = UUID.fromString("00001103-0000-1000-8000-00805F9B34FB")
        val PARCEL_UUID = ParcelUuid(OFFLINEMESH_BLE_UUID)
    }

    private val bluetoothManager: BluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter
    
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null
    
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var isAdvertising = false
    private var isScanning = false

    fun setupChannels(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    startAdvertising()
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(null)
                }
                "startScanning" -> {
                    startScanning()
                    result.success(null)
                }
                "stopScanning" -> {
                    stopScanning()
                    result.success(null)
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
                // Clean up when channel is closed
                stopAdvertising()
                stopScanning()
            }
        })
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            Log.d(TAG, "BLE advertising started successfully")
            sendEvent(mapOf("type" to "advertisingState", "state" to "started"))
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            Log.e(TAG, "BLE advertising failed with error code $errorCode")
            sendEvent(mapOf("type" to "error", "message" to "Advertising failed: $errorCode"))
            isAdvertising = false
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            super.onScanResult(callbackType, result)
            
            // Result is already filtered for our UUID, but double check
            val device = result.device
            val address = device.address
            val name = try { device.name } catch (e: SecurityException) { "Unknown" } ?: "Unknown"
            val rssi = result.rssi

            sendEvent(mapOf(
                "type" to "deviceDiscovered",
                "address" to address,
                "name" to name,
                "rssi" to rssi
            ))
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            super.onBatchScanResults(results)
            results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            Log.e(TAG, "BLE scan failed with error code $errorCode")
            sendEvent(mapOf("type" to "error", "message" to "Scanning failed: $errorCode"))
            isScanning = false
        }
    }

    private fun startAdvertising() {
        if (isAdvertising) return
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            Log.e(TAG, "Bluetooth not enabled")
            return
        }

        bleAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
        if (bleAdvertiser == null) {
            Log.e(TAG, "BLE Advertising not supported on this device")
            sendEvent(mapOf("type" to "error", "message" to "BLE Advertising not supported"))
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true) // We will eventually connect for messaging
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false) // Save space in packet
            .addServiceUuid(PARCEL_UUID)
            .build()

        try {
            bleAdvertiser?.startAdvertising(settings, data, advertiseCallback)
            isAdvertising = true
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: Missing BLUETOOTH_ADVERTISE permission", e)
            sendEvent(mapOf("type" to "error", "message" to "Missing advertise permission"))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start advertising", e)
        }
    }

    private fun stopAdvertising() {
        if (!isAdvertising) return
        try {
            bleAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException on stop advertising", e)
        }
        isAdvertising = false
        Log.d(TAG, "BLE advertising stopped")
        sendEvent(mapOf("type" to "advertisingState", "state" to "stopped"))
    }

    private fun startScanning() {
        if (isScanning) return
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) return

        bleScanner = bluetoothAdapter.bluetoothLeScanner
        if (bleScanner == null) {
            Log.e(TAG, "BLE Scanner is null")
            sendEvent(mapOf("type" to "error", "message" to "BLE Scanner not available"))
            return
        }

        val filters = listOf(
            ScanFilter.Builder()
                .setServiceUuid(PARCEL_UUID)
                .build()
        )

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY) // Use low latency while user is actively looking
            .build()

        try {
            bleScanner?.startScan(filters, settings, scanCallback)
            isScanning = true
            Log.d(TAG, "BLE scanning started")
            sendEvent(mapOf("type" to "scanningState", "state" to "started"))
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: Missing BLUETOOTH_SCAN permission", e)
            sendEvent(mapOf("type" to "error", "message" to "Missing scan permission"))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start scanning", e)
        }
    }

    private fun stopScanning() {
        if (!isScanning) return
        try {
            bleScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException on stop scanning", e)
        }
        isScanning = false
        Log.d(TAG, "BLE scanning stopped")
        sendEvent(mapOf("type" to "scanningState", "state" to "stopped"))
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }
}
