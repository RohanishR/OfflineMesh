import '../transport/transport_type.dart';

class BleDiscoveredDevice {
  final String address;
  final String name;
  final int rssi;
  final DateTime discoveryTime;
  final TransportType transport = TransportType.BLE;

  // This will be populated later if an exchange identifies the OfflineMesh ID
  String? offlineMeshId;

  BleDiscoveredDevice({
    required this.address,
    required this.name,
    required this.rssi,
    required this.discoveryTime,
    this.offlineMeshId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDiscoveredDevice &&
          runtimeType == other.runtimeType &&
          address == other.address;

  @override
  int get hashCode => address.hashCode;
}
