import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/cash_movement.dart';
import '../models/cashier_models.dart';
import 'offline_catalog_store.dart';
import 'offline_sale_queue.dart';
import '../models/user_profile.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ForbiddenException implements Exception {
  const ForbiddenException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the server responds with HTTP 401.
/// The app should intercept this and redirect to the login screen.
class UnauthorizedException implements Exception {
  const UnauthorizedException();

  @override
  String toString() => 'Sesi berakhir. Silakan login kembali.';
}

class ApiClient {
  ApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final OfflineCatalogStore _offlineCatalog = OfflineCatalogStore();
  String? _token;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Future<UserProfile?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('api_token');

    if (!isLoggedIn) {
      return null;
    }

    try {
      return await me();
    } catch (_) {
      _token = null;
      await prefs.remove('api_token');
      return null;
    }
  }

  Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final response = await _post(
      '/login',
      body: {
        'email': email,
        'password': password,
        'device_name': 'android-cashier',
      },
      authenticated: false,
    );

    _token = response['token'] as String?;
    final user = response['user'] as Map<String, dynamic>?;

    if (_token == null || user == null) {
      throw const ApiException('Response login tidak lengkap.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', _token!);

    return UserProfile.fromJson(user);
  }

  Future<UserProfile> me() async {
    final response = await _get('/me');
    final user = response['user'] as Map<String, dynamic>?;

    if (user == null) {
      throw const ApiException('Session tidak valid.');
    }

    return UserProfile.fromJson(user);
  }

  Future<void> logout() async {
    if (isLoggedIn) {
      try {
        await _post('/logout', body: {});
      } catch (_) {
        // Best-effort — clear local token regardless.
      }
    }

    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_token');
  }

  Future<CashierBootstrap> bootstrap() async {
    try {
      final response = await _get('/cashier/bootstrap');
      await _offlineCatalog.saveBootstrap(response);

      return CashierBootstrap.fromJson(response);
    } on NetworkException {
      final cached = await _offlineCatalog.bootstrap();
      if (cached != null) {
        return cached;
      }

      rethrow;
    }
  }

  Future<CashierSummary> summary() async {
    final response = await _get('/cashier/summary');

    return CashierSummary.fromJson(response);
  }

  Future<List<CashierProduct>> searchProducts(String search) async {
    try {
      final response = await _get(
        '/cashier/products',
        query: {'search': search},
      );
      final items = response['data'] as List<dynamic>? ?? [];

      return items
          .whereType<Map<String, dynamic>>()
          .map(CashierProduct.fromJson)
          .where((product) => product.id > 0)
          .toList();
    } on NetworkException {
      return _offlineCatalog.searchProducts(search);
    }
  }

  Future<List<CashierProduct>> availableProducts() async {
    try {
      final response = await _get('/cashier/products/available');
      final items = response['data'] as List<dynamic>? ?? [];

      final products = items
          .whereType<Map<String, dynamic>>()
          .map(CashierProduct.fromJson)
          .where((product) => product.id > 0)
          .toList();

      await _offlineCatalog.saveProducts(products);

      return products;
    } on NetworkException {
      return _offlineCatalog.products();
    }
  }

  Future<CashierProduct> productByBarcode(String barcode) async {
    try {
      final response = await _get(
        '/cashier/products/barcode',
        query: {'barcode': barcode},
      );

      return CashierProduct.fromJson(response['data'] as Map<String, dynamic>);
    } on NetworkException {
      final cached = await _offlineCatalog.findByBarcode(barcode);
      if (cached != null) {
        return cached;
      }

      throw const ApiException(
        'Produk tidak ditemukan di cache offline. Sync katalog saat online.',
      );
    }
  }

  Future<void> refreshOfflineCatalog() async {
    await availableProducts();
  }

  Future<List<CashierCustomer>> searchCustomers(String search) async {
    final response = await _get(
      '/cashier/customers',
      query: {'search': search},
    );
    final items = response['data'] as List<dynamic>? ?? [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(CashierCustomer.fromJson)
        .where((customer) => customer.id > 0)
        .toList();
  }

  Future<List<RecentSale>> recentSales() async {
    final response = await _get('/cashier/recent-sales');
    final items = response['data'] as List<dynamic>? ?? [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(RecentSale.fromJson)
        .where((sale) => sale.id > 0)
        .toList();
  }

  Future<CheckoutResult> receipt(int saleId, {int receiptColumns = 32}) async {
    final response = await _get(
      '/cashier/receipt/$saleId',
      query: {'receipt_columns': receiptColumns.toString()},
    );

    return CheckoutResult.fromJson(response);
  }

  Future<CashierShiftInfo?> shift() async {
    final response = await _get('/cashier/shift');
    final shift = response['active_shift'] as Map<String, dynamic>?;

    return shift == null ? null : CashierShiftInfo.fromJson(shift);
  }

  Future<CashierShiftInfo> openShift({
    required double openingCash,
    String? notes,
  }) async {
    final response = await _post(
      '/cashier/shift/open',
      body: {
        'opening_cash': openingCash,
        if (notes != null && notes.trim().isNotEmpty)
          'opening_notes': notes.trim(),
      },
    );
    final shift = response['active_shift'] as Map<String, dynamic>?;

    if (shift == null) {
      throw const ApiException('Response buka shift tidak lengkap.');
    }

    return CashierShiftInfo.fromJson(shift);
  }

  Future<CashierShiftInfo?> closeShift({
    required double closingCash,
    String? notes,
  }) async {
    final response = await _post(
      '/cashier/shift/close',
      body: {
        'closing_cash': closingCash,
        if (notes != null && notes.trim().isNotEmpty)
          'closing_notes': notes.trim(),
      },
    );
    final shift = response['closed_shift'] as Map<String, dynamic>?;

    return shift == null ? null : CashierShiftInfo.fromJson(shift);
  }

  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required int paymentMethodId,
    required double amount,
    String? referenceNumber,
    int? customerId,
    int redeemPoints = 0,
    int receiptColumns = 32,
  }) async {
    final response = await _post(
      '/cashier/checkout',
      body: {
        'items': items.map((item) => item.toCheckoutJson()).toList(),
        'payment_method_id': paymentMethodId,
        'amount': amount,
        if (referenceNumber != null && referenceNumber.trim().isNotEmpty)
          'reference_number': referenceNumber.trim(),
        'customer_id': customerId,
        if (redeemPoints > 0) 'redeem_points': redeemPoints,
        'receipt_columns': receiptColumns,
      },
    );

    return CheckoutResult.fromJson(response);
  }

  Future<String> syncOfflineSale(OfflineSaleDraft draft) async {
    final response = await _post(
      '/cashier/offline-sales/sync',
      body: draft.toSyncJson(),
    );

    return response['invoice_number'] as String? ?? '-';
  }

  // ─── Cash In / Out ────────────────────────────────────────────────────────

  Future<List<CashMovementModel>> cashMovements() async {
    final response = await _get('/cashier/cash-movements');
    final items = response['data'] as List<dynamic>? ?? [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(CashMovementModel.fromJson)
        .toList();
  }

  Future<CashMovementModel> createCashMovement({
    required String type,
    required double amount,
    required String notes,
    String? category,
  }) async {
    final response = await _post(
      '/cashier/cash-movements',
      body: {
        'type': type,
        'amount': amount,
        'notes': notes,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
      },
    );

    return CashMovementModel.fromJson(
      response['movement'] as Map<String, dynamic>,
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  final Duration _timeout = const Duration(
    seconds: AppConfig.httpTimeoutSeconds,
  );

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.baseUrl}$path',
      ).replace(queryParameters: query);
      final response = await _httpClient
          .get(uri, headers: _headers(authenticated: true))
          .timeout(_timeout);

      return _decode(response);
    } on SocketException {
      throw const NetworkException('Koneksi internet tidak tersedia.');
    } on http.ClientException {
      throw const NetworkException('Tidak bisa terhubung ke server.');
    } on TimeoutException {
      throw const NetworkException(
        'Koneksi ke server terlalu lama. Coba lagi.',
      );
    } on FormatException {
      throw const ApiException('Response server tidak valid.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    bool authenticated = true,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('${AppConfig.baseUrl}$path'),
            headers: _headers(authenticated: authenticated),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      return _decode(response);
    } on SocketException {
      throw const NetworkException('Koneksi internet tidak tersedia.');
    } on http.ClientException {
      throw const NetworkException('Tidak bisa terhubung ke server.');
    } on TimeoutException {
      throw const NetworkException(
        'Koneksi ke server terlalu lama. Coba lagi.',
      );
    } on FormatException {
      throw const ApiException('Response server tidak valid.');
    }
  }

  Map<String, String> _headers({required bool authenticated}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    // 401 → session expired, bubble up so the app can redirect to login.
    if (response.statusCode == 401) {
      _token = null;
      SharedPreferences.getInstance().then((p) => p.remove('api_token'));
      throw const UnauthorizedException();
    }

    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      final errors = body['errors'] as Map<String, dynamic>?;
      final firstError = errors == null || errors.isEmpty
          ? null
          : errors.values.first;
      final message =
          body['message'] as String? ??
          (firstError is List && firstError.isNotEmpty
              ? firstError.first.toString()
              : firstError?.toString()) ??
          'Request gagal (${response.statusCode}).';

      if (response.statusCode == 403) {
        throw ForbiddenException(message);
      }

      throw ApiException(message);
    }

    return body;
  }
}
