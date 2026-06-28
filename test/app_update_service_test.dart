import 'dart:convert';
import 'dart:io';

import 'package:flutter_cashier/models/app_update.dart';
import 'package:flutter_cashier/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('downloaded APK is reused for the same build and URL', () async {
    var requestCount = 0;
    final service = AppUpdateService(
      httpClient: MockClient((request) async {
        requestCount++;
        return http.Response.bytes(
          utf8.encode('fake apk bytes'),
          200,
          headers: {'content-length': '14'},
        );
      }),
    );
    final update = AppUpdateInfo(
      updateAvailable: true,
      latestVersion: '9.9.9',
      latestBuild: DateTime.now().millisecondsSinceEpoch.remainder(1000000000),
      apkUrl: 'https://example.test/yosy-cashier.apk',
      releaseNotes: 'Test update',
      required: false,
    );

    final first = await service.downloadApk(update);
    final second = await service.downloadApk(update);

    expect(first.path, second.path);
    expect(requestCount, 1);
    expect(await service.downloadedApk(update), isA<File>());

    await first.delete();
    final metadata = File('${first.path}.json');
    if (await metadata.exists()) {
      await metadata.delete();
    }
  });
}
