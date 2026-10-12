import '../transport/transport_type.dart';

class BluetoothDiscoveredDevice {
  final String address;
  final String name;
  final DateTime discoveryTime;
  final TransportType transport = TransportType.BLUETOOTH;

  // This will be populated later if an exchange identifies the OfflineMesh ID
  String? offlineMeshId;

  BluetoothDiscoveredDevice({
    required this.address,
    required this.name,
    required this.discoveryTime,
    this.offlineMeshId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDiscoveredDevice &&
          runtimeType == other.runtimeType &&
          address == other.address;

  @override
  int get hashCode => address.hashCode;
}
