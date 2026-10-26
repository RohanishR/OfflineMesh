import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_app/core/network/auth_service.dart';
import 'package:flutter_app/features/files/services/file_service.dart';

String token(int expiry) => 'header.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': expiry
        })))}.signature';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Expired and malformed sessions cannot be restored', () async {
    SharedPreferences.setMockInitialValues({'jwt_token': token(1)});
    final auth = AuthService(baseUrl: 'http://localhost');
    await auth.init();
    expect(auth.isAuthenticated, false);
    expect(
        (await SharedPreferences.getInstance()).getString('jwt_token'), isNull);
    expect(AuthService.tokenExpired('invalid'), true);
    expect(
        AuthService.tokenExpired(token(200),
            now: DateTime.fromMillisecondsSinceEpoch(100000)),
        false);
    expect(
        AuthService.tokenExpired(token(100),
            now: DateTime.fromMillisecondsSinceEpoch(100000)),
        true);
  });
  test('Metadata rejection requests sign-in with an actionable error',
      () async {
    final rejected = AuthService.rejectedSessions.first;
    await http.runWithClient(() async {
      final files =
          FileService(baseUrl: 'http://localhost', jwtToken: 'rejected');
      await expectLater(
          files.createMetadata(
              recipientOfflineMeshId: 'peer',
              originalFileName: 'a.txt',
              contentType: 'text/plain',
              fileSize: 1),
          throwsA(isA<SessionExpiredException>()));
    }, () => MockClient((_) async => http.Response('', 401)));
    expect(await rejected, 'rejected');
  });
  test('Server failures and forbidden resources do not invalidate a session',
      () {
    expect(() => AuthService.checkResponse(500, 'valid'), returnsNormally);
    expect(() => AuthService.checkResponse(403, 'valid'), returnsNormally);
  });
}
