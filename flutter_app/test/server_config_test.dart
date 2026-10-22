import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/core/config/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.initialize();
  });

  test('Normalizes an origin and rejects API paths and credentials', () {
    expect(AppConfig.normalizeUrl(' 192.168.137.1:8081/ '),
        'http://192.168.137.1:8081');
    for (final value in ['', 'ftp://host', 'http://user:pass@host',
      'http://host/api/auth/login', 'http://host?x=1']) {
      expect(() => AppConfig.normalizeUrl(value), throwsFormatException);
    }
  });

  test('Checks health without submitting a login', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/health');
      expect(request.headers.containsKey('authorization'), false);
      return http.Response('{"status":"UP","service":"OfflineMesh Backend"}', 200);
    });
    expect(await AppConfig.testConnection('http://host:8081', client: client), true);
    expect(await AppConfig.testConnection('http://host:8081',
      client: MockClient((_) async => http.Response('<html>Other server</html>', 200))), false);
  });

  test('Changing server persists it and removes the previous server token', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', 'old-server-token');
    await AppConfig.setBackendBaseUrl('192.168.137.1:8081');
    expect(prefs.getString('jwt_token'), isNull);
    expect(AppConfig.changes.value, 'http://192.168.137.1:8081');
    await AppConfig.initialize();
    expect(AppConfig.backendBaseUrl, 'http://192.168.137.1:8081');
  });
}
