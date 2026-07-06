import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/cashier_models.dart';

class OfflineSaleDraft {
  const OfflineSaleDraft({
    required this.localReference,
    required this.createdAt,
    required this.cartItems,
    required this.payment,
  });

  final String localReference;
  final DateTime createdAt;
  final List<Map<String, dynamic>> cartItems;
  final Map<String, dynamic> payment;

  factory OfflineSaleDraft.fromCart({
    required List<CartItem> cart,
    required int paymentMethodId,
    required double amount,
    required String? referenceNumber,
    required int? customerId,
    required int redeemPoints,
  }) {
    final now = DateTime.now();

    return OfflineSaleDraft(
      localReference: 'android-${now.microsecondsSinceEpoch}',
      createdAt: now,
      cartItems: cart.map((item) => item.toOfflineJson()).toList(),
      payment: {
        'payment_method_id': paymentMethodId,
        'amount': amount,
        if (referenceNumber != null && referenceNumber.trim().isNotEmpty)
          'reference_number': referenceNumber.trim(),
        'customer_id': customerId,
        if (redeemPoints > 0) 'redeem_points': redeemPoints,
      },
    );
  }

  factory OfflineSaleDraft.fromJson(Map<String, dynamic> json) {
    return OfflineSaleDraft(
      localReference: json['local_reference'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      cartItems: (json['cart_items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      payment: json['payment'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_reference': localReference,
      'created_at': createdAt.toIso8601String(),
      'cart_items': cartItems,
      'payment': payment,
    };
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'device_code': 'android-cashier',
      'device_name': 'Yosy Group Android Cashier',
      'local_reference': localReference,
      'cart_items': cartItems,
      'payment': payment,
    };
  }
}

class OfflineSaleQueue {
  static const _storageKey = 'yosy_group.offline_sales.queue';
  static const _backupStorageKey = 'yosy_group.offline_sales.backup';
  static const _backupUpdatedAtKey =
      'yosy_group.offline_sales.backup_updated_at';

  Future<List<OfflineSaleDraft>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OfflineSaleDraft.fromJson)
        .where(
          (draft) =>
              draft.localReference.isNotEmpty && draft.cartItems.isNotEmpty,
        )
        .toList();
  }

  Future<int> count() async {
    final items = await all();

    return items.length;
  }

  Future<void> enqueue(OfflineSaleDraft draft) async {
    var items = await all();

    // Prevent duplicate entries with the same local reference.
    if (items.any((d) => d.localReference == draft.localReference)) {
      return;
    }

    items.add(draft);

    // Cap queue size and drop the oldest entries if over the limit.
    if (items.length > AppConfig.offlineQueueMaxSize) {
      items = items.sublist(items.length - AppConfig.offlineQueueMaxSize);
    }

    await _save(items);
    await _backup(draft);
  }

  Future<void> remove(String localReference) async {
    final items = await all();
    await _save(
      items.where((draft) => draft.localReference != localReference).toList(),
    );
  }

  /// Clears all pending drafts. Use with caution.
  Future<void> clear() async {
    await _save([]);
  }

  Future<List<OfflineSaleDraft>> backupAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupStorageKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OfflineSaleDraft.fromJson)
        .where(
          (draft) =>
              draft.localReference.isNotEmpty && draft.cartItems.isNotEmpty,
        )
        .toList();
  }

  Future<int> backupCount() async {
    final items = await backupAll();

    return items.length;
  }

  Future<DateTime?> backupUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupUpdatedAtKey);

    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Future<String> backupJson() async {
    final items = await backupAll();

    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Yosy Group Android Cashier',
      'total': items.length,
      'offline_sales': items.map((draft) => draft.toJson()).toList(),
    });
  }

  Future<void> _save(List<OfflineSaleDraft> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((draft) => draft.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> _backup(OfflineSaleDraft draft) async {
    var items = await backupAll();

    if (items.any((d) => d.localReference == draft.localReference)) {
      return;
    }

    items.add(draft);

    final maxBackupSize = AppConfig.offlineQueueMaxSize * 3;
    if (items.length > maxBackupSize) {
      items = items.sublist(items.length - maxBackupSize);
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((item) => item.toJson()).toList());
    await prefs.setString(_backupStorageKey, encoded);
    await prefs.setString(
      _backupUpdatedAtKey,
      DateTime.now().toIso8601String(),
    );
  }
}
