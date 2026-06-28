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
    final cached = await downloadedApk(update);
    if (cached != null) {
      onProgress?.call(1);
      return cached;
    }

    final request = http.Request('GET', Uri.parse(update.apkUrl));
    final response = await _httpClient.send(request).timeout(_timeout);

    if (response.statusCode >= 400) {
      throw ApiException('Download APK gagal (${response.statusCode}).');
    }

    final contentLength = response.contentLength ?? 0;
    final file = await _apkDownloadFile(update.latestBuild);
    final partialFile = File('${file.path}.part');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    final sink = partialFile.openWrite();
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

    if (contentLength > 0 && received != contentLength) {
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      throw const ApiException('Download APK belum lengkap. Coba lagi.');
    }

    if (await file.exists()) {
      await file.delete();
    }

    await partialFile.rename(file.path);
    await _writeDownloadMetadata(update, file, received);

    onProgress?.call(1);
    return file;
  }

  Future<File?> downloadedApk(AppUpdateInfo update) async {
    final file = await _apkDownloadFile(update.latestBuild);
    if (!await file.exists()) {
      return null;
    }

    final metadata = await _downloadMetadata(file);
    if (metadata == null) {
      return null;
    }

    final build = metadata['build'] as int?;
    final apkUrl = metadata['apk_url'] as String?;
    final expectedSize = metadata['size'] as int?;
    final actualSize = await file.length();

    if (build != update.latestBuild || apkUrl != update.apkUrl) {
      return null;
    }

    if (actualSize <= 0) {
      return null;
    }

    if (expectedSize != null &&
        expectedSize > 0 &&
        actualSize != expectedSize) {
      return null;
    }

    return file;
  }

  Future<File> _apkDownloadFile(int buildNumber) async {
    final fileName = 'yosy-cashier-$buildNumber.apk';

    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('apkCachePath', {
          'fileName': fileName,
        });
        if (path != null && path.isNotEmpty) {
          return File(path);
        }
      } on PlatformException {
        // Fall back to system temp for tests or unsupported native builds.
      } on MissingPluginException {
        // Fall back when the native channel is not available.
      }
    }

    return File('${Directory.systemTemp.path}/$fileName');
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

  Future<Map<String, dynamic>?> _downloadMetadata(File apkFile) async {
    final file = File('${apkFile.path}.json');
    if (!await file.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeDownloadMetadata(
    AppUpdateInfo update,
    File apkFile,
    int size,
  ) async {
    final metadataFile = File('${apkFile.path}.json');
    await metadataFile.writeAsString(
      jsonEncode({
        'build': update.latestBuild,
        'version': update.latestVersion,
        'apk_url': update.apkUrl,
        'size': size,
        'downloaded_at': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }
}
