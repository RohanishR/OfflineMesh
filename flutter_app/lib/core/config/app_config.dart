/// Central application configuration.
/// Change [backendBaseUrl] here to switch between environments.
class AppConfig {
  AppConfig._();

  /// Development backend URL — reachable from a physical device on the LAN.
  static const String backendBaseUrl = 'http://10.201.201.159:8080';
}
