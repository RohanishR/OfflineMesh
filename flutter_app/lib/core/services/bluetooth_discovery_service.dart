import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/bluetooth_discovered_device.dart';

enum BluetoothDiscoveryState {
  initial,
  checkingPermissions,
  permissionDenied,
  bluetoothDisabled,
  scanning,
  idle
}

class BluetoothDiscoveryService {
  final _devices = <String, BluetoothDiscoveredDevice>{};
  StreamSubscription<BluetoothDiscoveryResult>? _discoveryStreamSubscription;

  final _stateController = StreamController<BluetoothDiscoveryState>.broadcast();
  Stream<BluetoothDiscoveryState> get stateStream => _stateController.stream;

  final _devicesController = StreamController<List<BluetoothDiscoveredDevice>>.broadcast();
  Stream<List<BluetoothDiscoveredDevice>> get devicesStream => _devicesController.stream;

  BluetoothDiscoveryState _currentState = BluetoothDiscoveryState.initial;

  List<BluetoothDiscoveredDevice> get discoveredDevices => _devices.values.toList();
  BluetoothDiscoveryState get currentState => _currentState;

  void _setState(BluetoothDiscoveryState state) {
    _currentState = state;
    _stateController.add(state);
  }

  Future<bool> _requestPermissions() async {
    _setState(BluetoothDiscoveryState.checkingPermissions);
    
    // Request modern Bluetooth permissions and location (required for discovery on many Android versions)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Location is mandatory for Bluetooth Classic discovery on Android < 12
    // On Android 12+, bluetoothScan/Connect are mandatory.
    // If permission handler says any required is permanently denied/denied, we fail.
    // To be flexible across Android versions, if any permission is explicitly denied, we handle it gracefully.
    
    // Since some devices might not have Android 12, permission_handler handles SDK version mapping.
    bool allGranted = true;
    for (var entry in statuses.entries) {
      if (entry.value.isDenied || entry.value.isPermanentlyDenied) {
        // location might be denied on Android 12+ but discovery still works if bluetoothScan is granted?
        // Let's be strict for simplicity: if the system asked and user denied, we fail.
        if (entry.key != Permission.location || statuses[Permission.bluetoothScan]?.isGranted != true) {
          allGranted = false;
        }
      }
    }

    if (!allGranted) {
      _setState(BluetoothDiscoveryState.permissionDenied);
      return false;
    }

    return true;
  }

  Future<bool> _checkBluetoothEnabled() async {
    bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled == false) {
      _setState(BluetoothDiscoveryState.bluetoothDisabled);
      // Optional: Prompt user to enable Bluetooth
      isEnabled = await FlutterBluetoothSerial.instance.requestEnable();
      if (isEnabled == false || isEnabled == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> startDiscovery() async {
    if (_currentState == BluetoothDiscoveryState.scanning) return;

    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) return;

    final isEnabled = await _checkBluetoothEnabled();
    if (!isEnabled) {
      _setState(BluetoothDiscoveryState.bluetoothDisabled);
      return;
    }

    _devices.clear();

    // 1. Instantly populate already paired / bonded devices
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      for (final device in bonded) {
        if (device.address.isNotEmpty) {
          final name = (device.name != null && device.name!.isNotEmpty) ? '${device.name} (Paired)' : 'Paired Device';
          _devices[device.address] = BluetoothDiscoveredDevice(
            address: device.address,
            name: name,
            discoveryTime: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
    }

    _devicesController.add(discoveredDevices);
    _setState(BluetoothDiscoveryState.scanning);

    try {
      _discoveryStreamSubscription = FlutterBluetoothSerial.instance.startDiscovery().listen(
        (BluetoothDiscoveryResult result) {
          final device = result.device;
          // Ignore devices without names or addresses
          if (device.address.isNotEmpty) {
            final name = device.name ?? 'Unknown Device';
            
            _devices[device.address] = BluetoothDiscoveredDevice(
              address: device.address,
              name: name,
              discoveryTime: DateTime.now(),
            );
            _devicesController.add(discoveredDevices);
          }
        },
        onDone: () {
          _setState(BluetoothDiscoveryState.idle);
        },
        onError: (e) {
          debugPrint('Bluetooth discovery error: $e');
          _setState(BluetoothDiscoveryState.idle);
        },
      );
    } catch (e) {
      debugPrint('Failed to start discovery: $e');
      _setState(BluetoothDiscoveryState.idle);
    }
  }

  Future<int?> requestDiscoverable([int duration = 300]) async {
    try {
      return await FlutterBluetoothSerial.instance.requestDiscoverable(duration);
    } catch (e) {
      debugPrint('Error requesting discoverable: $e');
      return null;
    }
  }

  void stopDiscovery() {
    _discoveryStreamSubscription?.cancel();
    _discoveryStreamSubscription = null;
    if (_currentState == BluetoothDiscoveryState.scanning) {
      _setState(BluetoothDiscoveryState.idle);
    }
  }

  void dispose() {
    stopDiscovery();
    _stateController.close();
    _devicesController.close();
  }
}
