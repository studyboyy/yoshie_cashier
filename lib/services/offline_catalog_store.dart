import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cashier_models.dart';

class OfflineCatalogStore {
  static const _bootstrapKey = 'yosy_group.cashier.bootstrap';
  static const _productsKey = 'yosy_group.cashier.products';
  static const _productsUpdatedAtKey = 'yosy_group.cashier.products_updated_at';

  Future<void> saveBootstrap(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bootstrapKey, jsonEncode(json));
  }

  Future<CashierBootstrap?> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bootstrapKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      return CashierBootstrap.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_bootstrapKey);
      return null;
    }
  }

  Future<void> saveProducts(List<CashierProduct> products) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _productsKey,
      jsonEncode(products.map((product) => product.toJson()).toList()),
    );
    await prefs.setString(
      _productsUpdatedAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<List<CashierProduct>> products() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_productsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final items = jsonDecode(raw) as List<dynamic>;
      return items
          .whereType<Map<String, dynamic>>()
          .map(CashierProduct.fromJson)
          .where((product) => product.id > 0 && product.stock > 0)
          .toList();
    } catch (_) {
      await prefs.remove(_productsKey);
      await prefs.remove(_productsUpdatedAtKey);
      return const [];
    }
  }

  Future<List<CashierProduct>> searchProducts(String query) async {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return const [];
    }

    final products = await this.products();
    return products
        .where((product) {
          final barcode = _normalize(product.barcode ?? '');
          final compactBarcode = barcode
              .replaceAll('DPT', '')
              .replaceAll('-', '');

          return _normalize(product.name).contains(normalized) ||
              _normalize(product.sku).contains(normalized) ||
              barcode == normalized ||
              compactBarcode == normalized;
        })
        .take(12)
        .toList();
  }

  Future<CashierProduct?> findByBarcode(String query) async {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return null;
    }

    final products = await this.products();
    for (final product in products) {
      final barcode = _normalize(product.barcode ?? '');
      final sku = _normalize(product.sku);
      final compactBarcode = barcode.replaceAll('DPT', '').replaceAll('-', '');

      if (barcode == normalized ||
          sku == normalized ||
          compactBarcode == normalized) {
        return product;
      }
    }

    return null;
  }

  Future<DateTime?> productsUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_productsUpdatedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<OfflineCatalogSnapshot> snapshot() async {
    final productList = await products();
    final updatedAt = await productsUpdatedAt();

    return OfflineCatalogSnapshot(
      productCount: productList.length,
      updatedAt: updatedAt,
    );
  }

  String _normalize(String value) {
    return value.trim().toUpperCase();
  }
}

class OfflineCatalogSnapshot {
  const OfflineCatalogSnapshot({
    required this.productCount,
    required this.updatedAt,
  });

  final int productCount;
  final DateTime? updatedAt;
}
