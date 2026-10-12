import 'package:flutter/material.dart';
import '../../../core/services/wifi_peer_discovery_service.dart';
import '../../../core/services/bluetooth_discovery_service.dart';
import '../../../core/services/ble_discovery_service.dart';
import '../../../core/models/discovered_peer.dart';
import '../../../core/models/bluetooth_discovered_device.dart';
import '../../../core/models/ble_discovered_device.dart';
import '../../../core/models/user.dart';

class NearbyDevicesScreen extends StatefulWidget {
  final UserProfile currentUser;
  final WifiPeerDiscoveryService discoveryService;
  final BluetoothDiscoveryService bluetoothDiscoveryService;
  final BleDiscoveryService bleDiscoveryService;
  
  const NearbyDevicesScreen({
    super.key, 
    required this.currentUser,
    required this.discoveryService,
    required this.bluetoothDiscoveryService,
    required this.bleDiscoveryService,
  });

  @override
  State<NearbyDevicesScreen> createState() => _NearbyDevicesScreenState();
}

class _NearbyDevicesScreenState extends State<NearbyDevicesScreen> {
  bool _isWifiDiscovering = false;

  @override
  void initState() {
    super.initState();
    _startWifiDiscovery();
  }

  @override
  void dispose() {
    // We let wifi discovery run, but we don't necessarily stop it here.
    widget.bluetoothDiscoveryService.stopDiscovery();
    widget.bleDiscoveryService.stopScanning();
    super.dispose();
  }

  void _startWifiDiscovery() async {
    await widget.discoveryService.startDiscovery(widget.currentUser);
    if (mounted) {
      setState(() {
        _isWifiDiscovering = widget.discoveryService.isDiscovering;
      });
    }
  }

  void _stopWifiDiscovery() {
    widget.discoveryService.stopDiscovery();
    if (mounted) {
      setState(() {
        _isWifiDiscovering = widget.discoveryService.isDiscovering;
      });
    }
  }

  void _toggleBluetoothDiscovery() {
    final btState = widget.bluetoothDiscoveryService.currentState;
    if (btState == BluetoothDiscoveryState.scanning) {
      widget.bluetoothDiscoveryService.stopDiscovery();
    } else {
      widget.bluetoothDiscoveryService.startDiscovery();
    }
  }

  Widget _buildWifiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Wi-Fi LAN', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: Icon(_isWifiDiscovering ? Icons.stop_circle : Icons.play_circle),
                tooltip: _isWifiDiscovering ? 'Stop Wi-Fi Scan' : 'Start Wi-Fi Scan',
                onPressed: _isWifiDiscovering ? _stopWifiDiscovery : _startWifiDiscovery,
              )
            ],
          ),
        ),
        if (_isWifiDiscovering)
          const LinearProgressIndicator(),
        StreamBuilder<List<DiscoveredPeer>>(
          stream: widget.discoveryService.peersStream,
          initialData: widget.discoveryService.peersStream.isBroadcast ? null : const [],
          builder: (context, snapshot) {
            final peers = snapshot.data ?? [];
            if (peers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: Text('No nearby Wi-Fi devices found.')),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: peers.length,
              itemBuilder: (context, index) {
                final peer = peers[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.wifi)),
                  title: Text(peer.displayName),
                  subtitle: Text('ID: ${peer.offlineMeshId}\nIP: ${peer.ipAddress}'),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        peer.isReachable ? Icons.check_circle : Icons.error,
                        color: peer.isReachable ? Colors.green : Colors.red,
                      ),
                      const Text('WIFI_LAN', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildBluetoothSection() {
    return StreamBuilder<BluetoothDiscoveryState>(
      stream: widget.bluetoothDiscoveryService.stateStream,
      initialData: widget.bluetoothDiscoveryService.currentState,
      builder: (context, stateSnapshot) {
        final btState = stateSnapshot.data ?? BluetoothDiscoveryState.idle;
        final isScanning = btState == BluetoothDiscoveryState.scanning;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bluetooth', style: Theme.of(context).textTheme.titleMedium),
                  ElevatedButton.icon(
                    onPressed: _toggleBluetoothDiscovery,
                    icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
                    label: Text(isScanning ? 'Stop Scan' : 'Scan Bluetooth'),
                  )
                ],
              ),
            ),
            if (isScanning || btState == BluetoothDiscoveryState.checkingPermissions)
              const LinearProgressIndicator(),
            
            // Status messages
            if (btState == BluetoothDiscoveryState.permissionDenied)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bluetooth or Location permission is required for discovery.', style: TextStyle(color: Colors.red)),
              ),
            if (btState == BluetoothDiscoveryState.bluetoothDisabled)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bluetooth is disabled. Please turn it on.', style: TextStyle(color: Colors.red)),
              ),
            
            // Device list
            StreamBuilder<List<BluetoothDiscoveredDevice>>(
              stream: widget.bluetoothDiscoveryService.devicesStream,
              initialData: widget.bluetoothDiscoveryService.discoveredDevices,
              builder: (context, devicesSnapshot) {
                final devices = devicesSnapshot.data ?? [];
                
                if (devices.isEmpty && !isScanning && btState == BluetoothDiscoveryState.idle) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('No Bluetooth devices found.')),
                  );
                }
                
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.bluetooth, color: Colors.white),
                      ),
                      title: Text(device.name),
                      subtitle: Text(device.address),
                      trailing: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth_connected, color: Colors.grey),
                          Text('BLUETOOTH', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _toggleBleDiscovery() {
    final state = widget.bleDiscoveryService.currentState;
    if (state == BleDiscoveryState.scanning) {
      widget.bleDiscoveryService.stopScanning();
    } else {
      widget.bleDiscoveryService.startScanning();
    }
  }

  Widget _buildBleSection() {
    return StreamBuilder<BleDiscoveryState>(
      stream: widget.bleDiscoveryService.stateStream,
      initialData: widget.bleDiscoveryService.currentState,
      builder: (context, stateSnapshot) {
        final bleState = stateSnapshot.data ?? BleDiscoveryState.idle;
        final isScanning = bleState == BleDiscoveryState.scanning;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('BLE', style: Theme.of(context).textTheme.titleMedium),
                  ElevatedButton.icon(
                    onPressed: _toggleBleDiscovery,
                    icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
                    label: Text(isScanning ? 'Stop Scan' : 'Scan BLE'),
                  )
                ],
              ),
            ),
            if (isScanning || bleState == BleDiscoveryState.checkingPermissions)
              const LinearProgressIndicator(),
            
            if (bleState == BleDiscoveryState.permissionDenied)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('BLE permissions denied. Please grant them in settings.', style: TextStyle(color: Colors.red)),
              )
            else if (bleState == BleDiscoveryState.bluetoothDisabled)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bluetooth is disabled. Please turn it on.', style: TextStyle(color: Colors.red)),
              )
            else
              StreamBuilder<List<BleDiscoveredDevice>>(
                stream: widget.bleDiscoveryService.devicesStream,
                initialData: widget.bleDiscoveryService.discoveredDevices,
                builder: (context, devicesSnapshot) {
                  final devices = devicesSnapshot.data ?? [];
                  if (devices.isEmpty) {
                    if (isScanning) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text('Scanning for OfflineMesh BLE devices...')),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: Text('No BLE devices found.')),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.bluetooth_audio, color: Colors.white),
                        ),
                        title: Text(device.name.isNotEmpty ? device.name : 'Unknown Device'),
                        subtitle: Text('Address: ${device.address}\nRSSI: ${device.rssi} dBm'),
                        isThreeLine: true,
                        trailing: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            Text('BLE', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Devices'),
      ),
      body: ListView(
        children: [
          _buildWifiSection(),
          _buildBluetoothSection(),
          _buildBleSection(),
        ],
      ),
    );
  }
}
