import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/cash_movement.dart';
import '../models/cashier_models.dart';
import 'offline_catalog_store.dart';
import 'offline_sale_history_store.dart';
import 'offline_sale_queue.dart';
import 'network_guard.dart';
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
  ApiClient({http.Client? httpClient, NetworkGuard? networkGuard})
    : _httpClient = httpClient ?? http.Client(),
      _networkGuard = networkGuard ?? NetworkGuard();

  static const _tokenKey = 'api_token';
  static const _userProfileKey = 'api_user_profile';
  static const _summaryCacheKey = 'cashier_summary_cache';

  final http.Client _httpClient;
  final NetworkGuard _networkGuard;
  final OfflineCatalogStore _offlineCatalog = OfflineCatalogStore();
  String? _token;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isServerCoolingDown => _networkGuard.isCoolingDown;
  NetworkGuardState get networkState => _networkGuard.state;
  Stream<NetworkGuardState> get networkChanges => _networkGuard.changes;

  void resetNetworkGuard() {
    _networkGuard.reset();
  }

  Future<UserProfile?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);

    if (!isLoggedIn) {
      return null;
    }

    try {
      final user = await me();
      await prefs.setString(_userProfileKey, jsonEncode(user.toJson()));

      return user;
    } on NetworkException {
      final cachedUser = _cachedUserProfile(prefs);
      if (cachedUser != null) {
        return cachedUser;
      }

      return null;
    } on UnauthorizedException {
      _token = null;
      await prefs.remove(_tokenKey);
      await prefs.remove(_userProfileKey);
      return null;
    } catch (_) {
      final cachedUser = _cachedUserProfile(prefs);
      if (cachedUser != null) {
        return cachedUser;
      }

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
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userProfileKey, jsonEncode(user));

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
    await prefs.remove(_tokenKey);
    await prefs.remove(_userProfileKey);
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
    try {
      final response = await _get('/cashier/summary');
      final serverSummary = CashierSummary.fromJson(response);
      final summary = await _summaryFromRecentSales(fallback: serverSummary);
      await _saveSummaryCache(summary);

      return summary;
    } on NetworkException {
      return await _cachedSummary() ?? await _offlineSummary();
    }
  }

  Future<CashierSummary> _summaryFromRecentSales({
    required CashierSummary fallback,
  }) async {
    try {
      final now = DateTime.now();
      final response = await _get(
        '/cashier/recent-sales',
        query: {
          'date':
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        },
      );
      final items = response['data'] as List<dynamic>? ?? [];
      final sales = items
          .whereType<Map<String, dynamic>>()
          .map(RecentSale.fromJson)
          .where((sale) => sale.id > 0)
          .toList();

      if (sales.isEmpty) {
        return fallback;
      }

      return CashierSummary(
        todaySalesTotal: sales.fold<double>(
          0,
          (total, sale) => total + sale.netTotal,
        ),
        todaySalesCount: sales.length,
        todayItemsCount: sales.fold<int>(
          0,
          (total, sale) =>
              total +
              sale.items.fold<int>(0, (sum, item) => sum + item.quantity),
        ),
        availableProductCount: fallback.availableProductCount,
        lowStockCount: fallback.lowStockCount,
      );
    } on NetworkException {
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _saveSummaryCache(CashierSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _summaryCacheKey,
      jsonEncode({
        'cached_at': DateTime.now().toIso8601String(),
        'summary': summary.toJson(),
      }),
    );
  }

  Future<CashierSummary?> _cachedSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_summaryCacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final summary = json['summary'];
      if (summary is Map<String, dynamic>) {
        return CashierSummary.fromJson(summary);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<CashierSummary> _offlineSummary() async {
    final history = await const OfflineSaleHistoryStore().all();
    final products = await _offlineCatalog.products();
    final now = DateTime.now();
    final todaySales = history.where((sale) {
      final paidAt = sale.paidAt;
      if (paidAt == null) {
        return false;
      }

      return paidAt.year == now.year &&
          paidAt.month == now.month &&
          paidAt.day == now.day;
    }).toList();

    return CashierSummary(
      todaySalesTotal: todaySales.fold<double>(
        0,
        (total, sale) => total + sale.netTotal,
      ),
      todaySalesCount: todaySales.length,
      todayItemsCount: todaySales.fold<int>(
        0,
        (total, sale) =>
            total + sale.items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
      availableProductCount: products.length,
      lowStockCount: products.where((product) => product.stock <= 3).length,
    );
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

  Future<List<RecentSale>> recentSales({DateTime? date}) async {
    try {
      final response = await _get(
        '/cashier/recent-sales',
        query: {
          if (date != null)
            'date':
                '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        },
      );
      final items = response['data'] as List<dynamic>? ?? [];

      return items
          .whereType<Map<String, dynamic>>()
          .map(RecentSale.fromJson)
          .where((sale) => sale.id > 0)
          .toList();
    } on NetworkException {
      final offlineSales = await const OfflineSaleHistoryStore().all();
      if (date == null) {
        return offlineSales;
      }

      return offlineSales.where((sale) {
        final paidAt = sale.paidAt;
        if (paidAt == null) {
          return false;
        }

        return paidAt.year == date.year &&
            paidAt.month == date.month &&
            paidAt.day == date.day;
      }).toList();
    }
  }

  Future<List<OfflineSaleStatus>> offlineSaleStatuses(
    Iterable<String> localReferences,
  ) async {
    final references = localReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList();

    if (references.isEmpty) {
      return const <OfflineSaleStatus>[];
    }

    final response = await _post(
      '/cashier/offline-sales/status',
      body: {'local_references': references},
    );
    final items = response['data'] as List<dynamic>? ?? [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(OfflineSaleStatus.fromJson)
        .toList();
  }

  Future<CheckoutResult> receipt(int saleId, {int receiptColumns = 32}) async {
    final response = await _get(
      '/cashier/receipt/$saleId',
      query: {'receipt_columns': receiptColumns.toString()},
    );

    return CheckoutResult.fromJson(response);
  }

  Future<SaleReturnResult> createSaleReturn({
    required int saleId,
    required List<SaleReturnItemRequest> items,
    required String reason,
  }) async {
    final response = await _post(
      '/cashier/sales/$saleId/returns',
      body: {
        'reason': reason.trim().isEmpty
            ? 'Retur dari aplikasi kasir'
            : reason.trim(),
        'items': items.map((item) => item.toJson()).toList(),
      },
    );

    return SaleReturnResult.fromJson(response);
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
    required String localReference,
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
        'local_reference': localReference,
        if (referenceNumber != null && referenceNumber.trim().isNotEmpty)
          'reference_number': referenceNumber.trim(),
        'customer_id': customerId,
        if (redeemPoints > 0) 'redeem_points': redeemPoints,
        'receipt_columns': receiptColumns,
      },
    );

    return CheckoutResult.fromJson(response);
  }

  Future<SyncedOfflineSale> syncOfflineSale(OfflineSaleDraft draft) async {
    final response = await _post(
      '/cashier/offline-sales/sync',
      body: draft.toSyncJson(),
    );

    final saleId = response['sale_id'];

    return SyncedOfflineSale(
      saleId: saleId is num
          ? saleId.toInt()
          : int.tryParse(saleId?.toString() ?? '') ?? 0,
      invoiceNumber: response['invoice_number'] as String? ?? '-',
    );
  }

  Future<RecentSale> returnPreview(int saleId) async {
    final response = await _get('/cashier/sales/$saleId/return');
    final sale = response['sale'] as Map<String, dynamic>? ?? const {};

    return RecentSale.fromJson(sale);
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

      final decoded = _decode(response);
      _networkGuard.recordSuccess();

      return decoded;
    } on SocketException catch (error) {
      final message = _socketFailureMessage(error);
      _networkGuard.recordFailure(message);
      throw NetworkException(message);
    } on http.ClientException {
      _networkGuard.recordFailure('Tidak bisa terhubung ke server.');
      throw const NetworkException('Tidak bisa terhubung ke server.');
    } on TimeoutException {
      _networkGuard.recordFailure('Koneksi ke server terlalu lama.');
      throw const NetworkException(
        'Koneksi ke server terlalu lama. Coba lagi.',
      );
    } on FormatException {
      _networkGuard.recordFailure('Response server tidak valid.');
      throw const NetworkException(
        'Server sedang tidak stabil. Mode offline dipakai dulu.',
      );
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

      final decoded = _decode(response);
      _networkGuard.recordSuccess();

      return decoded;
    } on SocketException catch (error) {
      final message = _socketFailureMessage(error);
      _networkGuard.recordFailure(message);
      throw NetworkException(message);
    } on http.ClientException {
      _networkGuard.recordFailure('Tidak bisa terhubung ke server.');
      throw const NetworkException('Tidak bisa terhubung ke server.');
    } on TimeoutException {
      _networkGuard.recordFailure('Koneksi ke server terlalu lama.');
      throw const NetworkException(
        'Koneksi ke server terlalu lama. Coba lagi.',
      );
    } on FormatException {
      _networkGuard.recordFailure('Response server tidak valid.');
      throw const NetworkException(
        'Server sedang tidak stabil. Mode offline dipakai dulu.',
      );
    }
  }

  Map<String, String> _headers({required bool authenticated}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
    };
  }

  String _socketFailureMessage(SocketException error) {
    final raw = [
      error.message,
      error.osError?.message,
    ].whereType<String>().join(' ').toLowerCase();

    if (raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('no address associated') ||
        raw.contains('temporary failure in name resolution')) {
      return 'Koneksi internet atau DNS belum tersedia. Mode offline dipakai dulu.';
    }

    return 'Server belum bisa dihubungi. Mode offline dipakai dulu.';
  }

  Map<String, dynamic> _decode(http.Response response) {
    // 401 → session expired, bubble up so the app can redirect to login.
    if (response.statusCode == 401) {
      _token = null;
      SharedPreferences.getInstance().then((p) async {
        await p.remove(_tokenKey);
        await p.remove(_userProfileKey);
      });
      throw const UnauthorizedException();
    }

    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      if (response.statusCode >= 500) {
        _networkGuard.recordFailure('Server error (${response.statusCode}).');
        throw NetworkException(
          'Server sedang gangguan (${response.statusCode}). Mode offline dipakai dulu.',
        );
      }

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

  UserProfile? _cachedUserProfile(SharedPreferences prefs) {
    final raw = prefs.getString(_userProfileKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

class SyncedOfflineSale {
  const SyncedOfflineSale({required this.saleId, required this.invoiceNumber});

  final int saleId;
  final String invoiceNumber;
}

class OfflineSaleStatus {
  const OfflineSaleStatus({
    required this.localReference,
    required this.status,
    this.serverReference,
    this.errorMessage,
  });

  final String localReference;
  final String status;
  final String? serverReference;
  final String? errorMessage;

  bool get isSynced => status == 'synced';

  factory OfflineSaleStatus.fromJson(Map<String, dynamic> json) {
    return OfflineSaleStatus(
      localReference: json['local_reference'] as String? ?? '',
      status: json['status'] as String? ?? 'not_received',
      serverReference: json['server_reference'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}
