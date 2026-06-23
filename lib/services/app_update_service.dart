import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/app_update.dart';
import 'api_client.dart';

class AppUpdateService {
  AppUpdateService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _channel = MethodChannel('yosy_group/app_update');

  final http.Client _httpClient;
  final Duration _timeout = const Duration(seconds: 20);

  Future<AppUpdateInfo> checkForUpdate() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/app/update').replace(
      queryParameters: {
        'platform': 'android',
        'version': AppConfig.appVersion,
        'build': AppConfig.appBuild.toString(),
      },
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        throw ApiException(
          body['message']?.toString() ??
              'Gagal mengecek update (${response.statusCode}).',
        );
      }

      return AppUpdateInfo.fromJson(body);
    } on SocketException {
      throw const NetworkException('Koneksi internet tidak tersedia.');
    } on TimeoutException {
      throw const NetworkException('Cek update terlalu lama. Coba lagi.');
    } on FormatException {
      throw const ApiException('Response update server tidak valid.');
    }
  }

  Future<File> downloadApk(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(update.apkUrl));
    final response = await _httpClient.send(request).timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException('Download APK gagal (${response.statusCode}).');
    }

    final contentLength = response.contentLength ?? 0;
    final file = File(
      '${Directory.systemTemp.path}/yosy-cashier-${update.latestBuild}.apk',
    );
    final sink = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }
    } finally {
      await sink.close();
    }

    onProgress?.call(1);
    return file;
  }

  Future<void> installApk(File apkFile) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
    } on PlatformException catch (error) {
      throw ApiException(
        error.message ?? 'Tidak bisa membuka installer update.',
      );
    }
  }
}
