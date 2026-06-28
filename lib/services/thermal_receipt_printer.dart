import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ThermalPrinterDevice {
  const ThermalPrinterDevice({
    required this.name,
    required this.address,
    required this.type,
  });

  final String name;
  final String address;
  final String type;

  factory ThermalPrinterDevice.fromJson(Map<dynamic, dynamic> json) {
    return ThermalPrinterDevice(
      name: json['name'] as String? ?? 'Printer Bluetooth',
      address: json['address'] as String? ?? '',
      type: json['type'] as String? ?? 'Bluetooth',
    );
  }
}

class ThermalPrinterSettings {
  const ThermalPrinterSettings({
    required this.autoPrint,
    required this.receiptColumns,
    required this.selectedPrinter,
  });

  final bool autoPrint;
  final int receiptColumns;
  final ThermalPrinterDevice? selectedPrinter;

  String get paperLabel => receiptColumns >= 42 ? '80mm' : '58mm';
}

class ThermalReceiptPrinter {
  static const _channel = MethodChannel('yosy_group/thermal_printer');
  static const _printerNameKey = 'yosy_group.receipt_printer.name';
  static const _printerAddressKey = 'yosy_group.receipt_printer.address';
  static const _printerTypeKey = 'yosy_group.receipt_printer.type';
  static const _autoPrintKey = 'yosy_group.receipt_printer.auto_print';
  static const _receiptColumnsKey = 'yosy_group.receipt_printer.columns';
  static const _logoPathKey = 'yosy_group.receipt_printer.logo_path';

  // ─── Logo management ─────────────────────────────────────────────────────

  Future<void> saveLogoPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_logoPathKey);
    } else {
      await prefs.setString(_logoPathKey, path);
    }
  }

  Future<String?> logoPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_logoPathKey);
  }

  /// Download logo dari server. Jika gagal, pakai logo bawaan APK.
  Future<Uint8List?> fetchLogoBytes() async {
    final path = await logoPath();
    if (path == null || path.isEmpty) {
      return _fallbackLogoBytes();
    }

    try {
      final response = await http
          .get(_logoUri(path))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {
      // Gagal download logo — lanjutkan cetak tanpa logo
    }
    return _fallbackLogoBytes();
  }

  Uri _logoUri(String path) {
    final trimmed = path.trim();
    final directUri = Uri.tryParse(trimmed);

    if (directUri != null && directUri.hasScheme) {
      return directUri;
    }

    final baseUrl = AppConfig.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final storagePath = trimmed.startsWith('storage/')
        ? trimmed
        : 'storage/$trimmed';

    return Uri.parse('$baseUrl/$storagePath');
  }

  Future<Uint8List?> _fallbackLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/brand.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<List<ThermalPrinterDevice>> pairedPrinters() async {
    try {
      final response = await _channel.invokeMethod<List<dynamic>>(
        'listBondedPrinters',
      );

      return (response ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map(ThermalPrinterDevice.fromJson)
          .where((device) => device.address.isNotEmpty)
          .toList();
    } on PlatformException catch (exception) {
      throw PrinterException(
        exception.message ?? 'Gagal membaca daftar printer Bluetooth.',
      );
    }
  }

  Future<ThermalPrinterDevice?> selectedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_printerAddressKey);

    if (address == null || address.isEmpty) {
      return null;
    }

    return ThermalPrinterDevice(
      name: prefs.getString(_printerNameKey) ?? 'Printer Bluetooth',
      address: address,
      type: prefs.getString(_printerTypeKey) ?? 'Bluetooth',
    );
  }

  Future<void> saveSelectedPrinter(ThermalPrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerNameKey, printer.name);
    await prefs.setString(_printerAddressKey, printer.address);
    await prefs.setString(_printerTypeKey, printer.type);
  }

  Future<void> clearSelectedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerNameKey);
    await prefs.remove(_printerAddressKey);
    await prefs.remove(_printerTypeKey);
    await prefs.setBool(_autoPrintKey, false);
  }

  Future<ThermalPrinterSettings> settings() async {
    final prefs = await SharedPreferences.getInstance();
    final printer = await selectedPrinter();

    return ThermalPrinterSettings(
      autoPrint: prefs.getBool(_autoPrintKey) ?? false,
      receiptColumns: _normalizeColumns(prefs.getInt(_receiptColumnsKey) ?? 32),
      selectedPrinter: printer,
    );
  }

  Future<void> setAutoPrint(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPrintKey, enabled);
  }

  Future<void> setReceiptColumns(int columns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_receiptColumnsKey, _normalizeColumns(columns));
  }

  Future<int> receiptColumns() async {
    final prefs = await SharedPreferences.getInstance();

    return _normalizeColumns(prefs.getInt(_receiptColumnsKey) ?? 32);
  }

  Future<void> printReceipt({
    required ThermalPrinterDevice printer,
    required String receiptText,
  }) async {
    final logoBytes = await fetchLogoBytes();
    final columns = await receiptColumns();
    final safeReceiptText = receiptText.trim().isEmpty
        ? 'Yosy Group\nStruk tidak tersedia\n'
        : receiptText;

    try {
      await saveSelectedPrinter(printer);
      await _channel.invokeMethod<bool>('printReceipt', {
        'address': printer.address,
        'receiptText': safeReceiptText,
        'feedLines': 4,
        'logoMaxWidthDots': columns >= 42 ? 360 : 240,
        ...?(logoBytes == null ? null : {'logoBytes': logoBytes}),
      });
    } on PlatformException catch (exception) {
      throw PrinterException(exception.message ?? 'Gagal mencetak struk.');
    }
  }

  int _normalizeColumns(int columns) {
    return columns >= 42 ? 42 : 32;
  }
}
