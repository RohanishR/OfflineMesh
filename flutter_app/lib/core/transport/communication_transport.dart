import 'transport_type.dart';

abstract class CommunicationTransport {
  TransportType get transportType;
  Future<void> initialize();
  Future<void> shutdown();
}
