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
    this.syncStatus = 'pending',
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  final String localReference;
  final DateTime createdAt;
  final List<Map<String, dynamic>> cartItems;
  final Map<String, dynamic> payment;
  final String syncStatus;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;

  factory OfflineSaleDraft.fromCart({
    required List<CartItem> cart,
    required int paymentMethodId,
    required double amount,
    required String? referenceNumber,
    required int? customerId,
    required int redeemPoints,
    String? localReference,
  }) {
    final now = DateTime.now();

    return OfflineSaleDraft(
      localReference: localReference ?? nextLocalReference(),
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

  static String nextLocalReference() {
    return 'android-${DateTime.now().microsecondsSinceEpoch}';
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
      syncStatus: json['sync_status'] as String? ?? 'pending',
      attemptCount: json['attempt_count'] is num
          ? (json['attempt_count'] as num).toInt()
          : int.tryParse(json['attempt_count']?.toString() ?? '') ?? 0,
      lastAttemptAt: DateTime.tryParse(
        json['last_attempt_at']?.toString() ?? '',
      )?.toLocal(),
      lastError: json['last_error'] as String?,
    );
  }

  OfflineSaleDraft copyWith({
    String? syncStatus,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return OfflineSaleDraft(
      localReference: localReference,
      createdAt: createdAt,
      cartItems: cartItems,
      payment: payment,
      syncStatus: syncStatus ?? this.syncStatus,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_reference': localReference,
      'created_at': createdAt.toIso8601String(),
      'cart_items': cartItems,
      'payment': payment,
      'sync_status': syncStatus,
      'attempt_count': attemptCount,
      if (lastAttemptAt != null)
        'last_attempt_at': lastAttemptAt!.toIso8601String(),
      if ((lastError ?? '').trim().isNotEmpty) 'last_error': lastError,
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
    final localReference = _normalizeReference(draft.localReference);

    // Prevent duplicate entries with the same local reference.
    if (items.any(
      (d) => _normalizeReference(d.localReference) == localReference,
    )) {
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
    final normalizedReference = _normalizeReference(localReference);
    final items = await all();
    await _save(
      items
          .where(
            (draft) =>
                _normalizeReference(draft.localReference) !=
                normalizedReference,
          )
          .toList(),
    );
  }

  Future<void> markAttempt(String localReference) async {
    await _updateDraft(
      localReference,
      (draft) => draft.copyWith(
        syncStatus: 'syncing',
        attemptCount: draft.attemptCount + 1,
        lastAttemptAt: DateTime.now(),
        clearLastError: true,
      ),
    );
  }

  Future<void> markFailed(String localReference, String error) async {
    await _updateDraft(
      localReference,
      (draft) => draft.copyWith(
        syncStatus: 'failed',
        lastAttemptAt: DateTime.now(),
        lastError: error.trim().isEmpty ? 'Sync gagal.' : error.trim(),
      ),
    );
  }

  Future<void> markPending(String localReference) async {
    await _updateDraft(
      localReference,
      (draft) => draft.copyWith(syncStatus: 'pending'),
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

  Future<void> _updateDraft(
    String localReference,
    OfflineSaleDraft Function(OfflineSaleDraft draft) update,
  ) async {
    final normalizedReference = _normalizeReference(localReference);
    final items = await all();
    var changed = false;
    final updated = items.map((draft) {
      if (_normalizeReference(draft.localReference) != normalizedReference) {
        return draft;
      }

      changed = true;
      return update(draft);
    }).toList();

    if (changed) {
      await _save(updated);
    }
  }

  Future<void> _backup(OfflineSaleDraft draft) async {
    var items = await backupAll();

    final localReference = _normalizeReference(draft.localReference);
    if (items.any(
      (d) => _normalizeReference(d.localReference) == localReference,
    )) {
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

  String _normalizeReference(String value) {
    return value.trim().toUpperCase();
  }
}
