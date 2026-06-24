import 'dart:io';

import 'package:flutter_cashier/models/user_profile.dart';
import 'package:flutter_cashier/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restoreSession keeps cached user when network is unavailable', () async {
    SharedPreferences.setMockInitialValues({
      'api_token': 'token-123',
      'api_user_profile':
          '{"id":7,"name":"Kasir Depato","email":"kasir@example.test","role":"cashier"}',
    });

    final api = ApiClient(
      httpClient: MockClient((_) async {
        throw const SocketException('offline');
      }),
    );

    final user = await api.restoreSession();

    expect(user, isA<UserProfile>());
    expect(user?.id, 7);
    expect(user?.name, 'Kasir Depato');
    expect(api.isLoggedIn, isTrue);
  });

  test(
    'restoreSession clears local session when server returns unauthorized',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_token': 'expired-token',
        'api_user_profile':
            '{"id":7,"name":"Kasir Depato","email":"kasir@example.test","role":"cashier"}',
      });

      final api = ApiClient(
        httpClient: MockClient((_) async {
          return http.Response('{"message":"Unauthenticated."}', 401);
        }),
      );

      final user = await api.restoreSession();
      final prefs = await SharedPreferences.getInstance();

      expect(user, isNull);
      expect(api.isLoggedIn, isFalse);
      expect(prefs.getString('api_token'), isNull);
      expect(prefs.getString('api_user_profile'), isNull);
    },
  );
}
