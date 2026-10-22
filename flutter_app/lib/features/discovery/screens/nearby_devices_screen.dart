import '../../../core/ui/mesh_widgets.dart';
import 'package:flutter/material.dart';
import '../../../core/services/wifi_peer_discovery_service.dart';
import '../../../core/services/bluetooth_discovery_service.dart';
import '../../../core/services/ble_discovery_service.dart';
import '../../../core/models/discovered_peer.dart';
import '../../../core/models/bluetooth_discovered_device.dart';
import '../../../core/models/ble_discovered_device.dart';
import '../../../core/models/user.dart';
import '../../../core/config/app_config.dart';
import '../../../core/ui/server_config_dialog.dart';

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
  String? _wifiError;

  @override
  void initState() {
    super.initState();
    _startAllDiscovery();
  }

  void _startAllDiscovery() {
    _startWifiDiscovery();
    widget.bluetoothDiscoveryService.startDiscovery();
    widget.bleDiscoveryService.startAdvertising();
    widget.bleDiscoveryService.startScanning();
  }

  @override
  void dispose() {
    widget.bluetoothDiscoveryService.stopDiscovery();
    widget.bleDiscoveryService.stopScanning();
    super.dispose();
  }

  void _startWifiDiscovery() async {
    try {
      await widget.discoveryService.startDiscovery(widget.currentUser);
      if (mounted)
        setState(() {
          _isWifiDiscovering = widget.discoveryService.isDiscovering;
          _wifiError = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _isWifiDiscovering = false;
          _wifiError =
              'Wi-Fi discovery unavailable. Check your network and permissions, then try again.';
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
    final ips = widget.discoveryService.activeIps;
    final hasWifiOrHotspot = widget.discoveryService.hasLocalWifiOrHotspot;

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
                icon: Icon(
                    _isWifiDiscovering ? Icons.stop_circle : Icons.play_circle),
                tooltip:
                    _isWifiDiscovering ? 'Stop Wi-Fi Scan' : 'Start Wi-Fi Scan',
                onPressed: _isWifiDiscovering
                    ? _stopWifiDiscovery
                    : _startWifiDiscovery,
              )
            ],
          ),
        ),
        if (ips.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
            child: Text(
              'Local IP: ${ips.join(", ")}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Server: ${AppConfig.backendBaseUrl} (Local Wi-Fi)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              InkWell(
                onTap: () {
                  ServerConfigDialog.show(context, onSaved: () {
                    setState(() {});
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(Icons.edit, size: 14, color: MeshColors.blue),
                ),
              ),
            ],
          ),
        ),
        if (!hasWifiOrHotspot && _isWifiDiscovering)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Not connected to Wi-Fi. Connect both devices to the same Wi-Fi network or Mobile Hotspot.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        if (_wifiError != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_wifiError!)),
        if (_isWifiDiscovering) const LinearProgressIndicator(),
        StreamBuilder<List<DiscoveredPeer>>(
          stream: widget.discoveryService.peersStream,
          initialData:
              widget.discoveryService.peersStream.isBroadcast ? null : const [],
          builder: (context, snapshot) {
            final peers = snapshot.data ?? [];
            if (peers.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    _isWifiDiscovering
                        ? 'Broadcasting presence on port 45454...'
                        : 'No nearby Wi-Fi devices found.',
                  ),
                ),
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
                  subtitle:
                      Text('ID: ${peer.offlineMeshId}\nIP: ${peer.ipAddress}'),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        peer.isReachable ? Icons.check_circle : Icons.error,
                        color: peer.isReachable
                            ? MeshColors.blue
                            : MeshColors.orange,
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
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bluetooth', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final res = await widget.bluetoothDiscoveryService
                              .requestDiscoverable(300);
                          if (context.mounted && res != null && res > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Device is discoverable for $res seconds.'),
                                backgroundColor: MeshColors.blue,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Make Visible'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _toggleBluetoothDiscovery,
                        icon: Icon(isScanning
                            ? Icons.stop
                            : Icons.bluetooth_searching),
                        label: Text(isScanning ? 'Stop' : 'Scan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isScanning ||
                btState == BluetoothDiscoveryState.checkingPermissions)
              const LinearProgressIndicator(),

            // Status messages
            if (btState == BluetoothDiscoveryState.permissionDenied)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                    'Bluetooth or Location permission is required for discovery.',
                    style: TextStyle(color: MeshColors.orange)),
              ),
            if (btState == BluetoothDiscoveryState.bluetoothDisabled)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bluetooth is disabled. Please turn it on.',
                    style: TextStyle(color: MeshColors.orange)),
              ),

            // Device list
            StreamBuilder<List<BluetoothDiscoveredDevice>>(
              stream: widget.bluetoothDiscoveryService.devicesStream,
              initialData: widget.bluetoothDiscoveryService.discoveredDevices,
              builder: (context, devicesSnapshot) {
                final devices = devicesSnapshot.data ?? [];

                if (devices.isEmpty &&
                    !isScanning &&
                    btState == BluetoothDiscoveryState.idle) {
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
                        backgroundColor: MeshColors.navy,
                        child: Icon(Icons.bluetooth, color: Colors.white),
                      ),
                      title: Text(device.name),
                      subtitle: Text(device.address),
                      trailing: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth, color: MeshColors.blue),
                          Text('Discovered', style: TextStyle(fontSize: 10)),
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
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Discovered',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: MeshColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Advertising',
                          style: TextStyle(
                              fontSize: 10,
                              color: MeshColors.blue,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _toggleBleDiscovery,
                    icon: Icon(
                        isScanning ? Icons.stop : Icons.bluetooth_searching),
                    label: Text(isScanning ? 'Stop' : 'Scan'),
                  )
                ],
              ),
            ),
            if (isScanning || bleState == BleDiscoveryState.checkingPermissions)
              const LinearProgressIndicator(),
            if (bleState == BleDiscoveryState.permissionDenied)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                    'BLE permissions denied. Please grant them in settings.',
                    style: TextStyle(color: MeshColors.orange)),
              )
            else if (bleState == BleDiscoveryState.bluetoothDisabled)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bluetooth is disabled. Please turn it on.',
                    style: TextStyle(color: MeshColors.orange)),
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
                        child: Center(
                            child: Text(
                                'Scanning for OfflineMesh BLE devices...')),
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
                          backgroundColor: MeshColors.navy,
                          child:
                              Icon(Icons.bluetooth_audio, color: Colors.white),
                        ),
                        title: Text(device.name.isNotEmpty
                            ? device.name
                            : 'Unknown Device'),
                        subtitle: Text(
                            'Address: ${device.address}\nRSSI: ${device.rssi} dBm'),
                        isThreeLine: true,
                        trailing: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle,
                                color: MeshColors.blue),
                            Text('Discovered', style: TextStyle(fontSize: 10)),
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
  Widget build(BuildContext context) => MeshPage(
        title: 'Nearby',
        subtitle: 'Find a connection, closer to you.',
        child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              StreamBuilder<BluetoothDiscoveryState>(
                  stream: widget.bluetoothDiscoveryService.stateStream,
                  initialData: widget.bluetoothDiscoveryService.currentState,
                  builder: (context, bt) => StreamBuilder<BleDiscoveryState>(
                      stream: widget.bleDiscoveryService.stateStream,
                      initialData: widget.bleDiscoveryService.currentState,
                      builder: (context, ble) {
                        final active = _isWifiDiscovering ||
                            bt.data == BluetoothDiscoveryState.scanning ||
                            ble.data == BleDiscoveryState.scanning;
                        return Column(children: [
                          DiscoveryRadar(scanning: active),
                          const SizedBox(height: 12),
                          Text(
                              active
                                  ? 'Discovery in progress'
                                  : 'Ready when you are',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                              'Devices appear below when discovered. Discovery does not mean connected.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall)
                        ]);
                      })),
              const SizedBox(height: 24),
              GlassSurface(
                  padding: const EdgeInsets.all(4), child: _buildWifiSection()),
              const SizedBox(height: 16),
              GlassSurface(
                  padding: const EdgeInsets.all(4),
                  child: _buildBluetoothSection()),
              const SizedBox(height: 16),
              GlassSurface(
                  padding: const EdgeInsets.all(4), child: _buildBleSection()),
            ]),
      );
}
