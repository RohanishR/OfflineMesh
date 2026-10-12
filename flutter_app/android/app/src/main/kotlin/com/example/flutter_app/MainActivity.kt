package com.example.flutter_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.offlinemesh/bluetooth"
    private val EVENT_CHANNEL = "com.offlinemesh/bluetooth/events"
    private val bluetoothManager = BluetoothMessagingManager()

    private val FILE_CHANNEL = "com.offlinemesh/bluetooth_file"
    private val FILE_EVENT_CHANNEL = "com.offlinemesh/bluetooth_file/events"
    private val bluetoothFileManager by lazy { BluetoothFileTransferManager(this) }

    private val BLE_DISCOVERY_CHANNEL = "com.offlinemesh/ble_discovery"
    private val BLE_DISCOVERY_EVENT_CHANNEL = "com.offlinemesh/ble_discovery/events"
    private val bleDiscoveryManager by lazy { BleDiscoveryManager(this) }

    private val BLE_MESSAGING_CHANNEL = "com.offlinemesh/ble_messaging"
    private val BLE_MESSAGING_EVENT_CHANNEL = "com.offlinemesh/ble_messaging/events"
    private val bleMessagingManager by lazy { BleMessagingManager(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        bluetoothManager.setupChannels(methodChannel, eventChannel)

        val fileMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
        val fileEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_EVENT_CHANNEL)
        bluetoothFileManager.setupChannels(fileMethodChannel, fileEventChannel)

        val bleMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_DISCOVERY_CHANNEL)
        val bleEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_DISCOVERY_EVENT_CHANNEL)
        bleDiscoveryManager.setupChannels(bleMethodChannel, bleEventChannel)

        val bleMsgMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_MESSAGING_CHANNEL)
        val bleMsgEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_MESSAGING_EVENT_CHANNEL)
        bleMessagingManager.setupChannels(bleMsgMethodChannel, bleMsgEventChannel)
    }
}
