import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

import '../models/ble_discovered_device.dart';

enum BleDiscoveryState {
  initial,
  checkingPermissions,
  permissionDenied,
  bluetoothDisabled,
  scanning,
  advertising,
  idle
}

class BleDiscoveryService {
  static const MethodChannel _channel = MethodChannel('com.offlinemesh/ble_discovery');
  static const EventChannel _eventChannel = EventChannel('com.offlinemesh/ble_discovery/events');

  final _devices = <String, BleDiscoveredDevice>{};
  
  final _stateController = StreamController<BleDiscoveryState>.broadcast();
  Stream<BleDiscoveryState> get stateStream => _stateController.stream;

  final _devicesController = StreamController<List<BleDiscoveredDevice>>.broadcast();
  Stream<List<BleDiscoveredDevice>> get devicesStream => _devicesController.stream;

  BleDiscoveryState _currentState = BleDiscoveryState.initial;

  List<BleDiscoveredDevice> get discoveredDevices => _devices.values.toList();
  BleDiscoveryState get currentState => _currentState;

  StreamSubscription? _eventSubscription;
  Timer? _scanTimeoutTimer;

  void initialize() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        _handleNativeEvent(Map<String, dynamic>.from(event));
      }
    });

    startAdvertising().catchError((e) {
      debugPrint('Error auto-starting BLE advertising: $e');
    });
  }

  void _updateState(BleDiscoveryState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(_currentState);
    }
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String;

    switch (type) {
      case 'scanningState':
        final state = event['state'] as String;
        if (state == 'started') {
          _updateState(BleDiscoveryState.scanning);
        } else if (state == 'stopped') {
          _updateState(BleDiscoveryState.idle);
        }
        break;
      case 'advertisingState':
        // Optional: track advertising state if needed
        break;
      case 'deviceDiscovered':
        final address = event['address'] as String;
        final name = event['name'] as String;
        final rssi = event['rssi'] as int;
        
        final device = BleDiscoveredDevice(
          address: address,
          name: name,
          rssi: rssi,
          discoveryTime: DateTime.now(),
        );
        
        _devices[address] = device;
        _devicesController.add(discoveredDevices);
        break;
      case 'error':
        debugPrint('BLE Error: ${event['message']}');
        break;
    }
  }

  Future<bool> _requestPermissions() async {
    _updateState(BleDiscoveryState.checkingPermissions);

    Map<Permission, PermissionStatus> statuses;

    if (Platform.isAndroid) {
      // Android 12+ requires specific BLE permissions
      statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ].request();

      final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final locationGranted = statuses[Permission.location]?.isGranted ?? false;

      // On Android 12+, scan and connect are sufficient. On older Android, location is required.
      var canProceed = (scanGranted && connectGranted) || locationGranted;
      if (!canProceed) {
        final isScanOk = await Permission.bluetoothScan.isGranted;
        final isConnOk = await Permission.bluetoothConnect.isGranted;
        final isLocOk = await Permission.location.isGranted;
        canProceed = (isScanOk && isConnOk) || isLocOk;
      }

      if (!canProceed) {
        _updateState(BleDiscoveryState.permissionDenied);
        return false;
      }
    } else {
      statuses = await [
        Permission.bluetooth,
        Permission.location,
      ].request();

      bool allGranted = true;
      for (var status in statuses.values) {
        if (!status.isGranted) {
          allGranted = false;
          break;
        }
      }

      if (!allGranted) {
        _updateState(BleDiscoveryState.permissionDenied);
        return false;
      }
    }

    return true;
  }

  Future<void> startScanning() async {
    if (_currentState == BleDiscoveryState.scanning) return;

    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) return;

    // Ensure we are advertising so other devices see us while we scan
    startAdvertising().catchError((e) {
      debugPrint('Error advertising during scan: $e');
    });

    try {
      // Clear previous devices
      _devices.clear();
      _devicesController.add(discoveredDevices);
      
      await _channel.invokeMethod('startScanning');
      
      // Auto-stop scanning after 12 seconds to save battery
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = Timer(const Duration(seconds: 12), () {
        stopScanning();
      });
      
    } catch (e) {
      debugPrint('Error starting BLE scan: $e');
      _updateState(BleDiscoveryState.idle);
    }
  }

  Future<void> stopScanning() async {
    _scanTimeoutTimer?.cancel();
    try {
      await _channel.invokeMethod('stopScanning');
    } catch (e) {
      debugPrint('Error stopping BLE scan: $e');
    }
    _updateState(BleDiscoveryState.idle);
  }
  
  Future<void> startAdvertising() async {
    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) return;

    try {
      await _channel.invokeMethod('startAdvertising');
    } catch (e) {
      debugPrint('Error starting BLE advertise: $e');
    }
  }
  
  Future<void> stopAdvertising() async {
    try {
      await _channel.invokeMethod('stopAdvertising');
    } catch (e) {
      debugPrint('Error stopping BLE advertise: $e');
    }
  }

  void shutdown() {
    stopScanning();
    stopAdvertising();
    _eventSubscription?.cancel();
  }
}
