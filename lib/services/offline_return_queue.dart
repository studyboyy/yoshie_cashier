import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cashier_models.dart';

class OfflineReturnDraft {
  const OfflineReturnDraft({
    required this.localReference,
    required this.reason,
    required this.items,
    required this.createdAt,
  });

  final String localReference;
  final String reason;
  final List<SaleReturnItemRequest> items;
  final DateTime createdAt;

  factory OfflineReturnDraft.fromJson(Map<String, dynamic> json) {
    return OfflineReturnDraft(
      localReference: json['local_reference'] as String? ?? '',
      reason: json['reason'] as String? ?? 'Retur offline',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => SaleReturnItemRequest(
              saleItemId: _asInt(item['sale_item_id']),
              productId: _asInt(item['product_id']),
              qty: _asInt(item['qty']),
              condition: item['condition'] as String? ?? 'sellable',
            ),
          )
          .where((item) => item.qty > 0 && item.productId > 0)
          .toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_reference': localReference,
      'reason': reason,
      'items': items.map((item) => item.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class OfflineReturnQueue {
  const OfflineReturnQueue();

  static const _storageKey = 'yosy_group.offline_returns.queue';

  Future<List<OfflineReturnDraft>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(OfflineReturnDraft.fromJson)
          .where(
            (draft) =>
                draft.localReference.isNotEmpty && draft.items.isNotEmpty,
          )
          .toList();
    } catch (_) {
      await prefs.remove(_storageKey);
      return const [];
    }
  }

  Future<void> enqueue(OfflineReturnDraft draft) async {
    final drafts = await all();
    await _save([...drafts, draft]);
  }

  Future<List<OfflineReturnDraft>> forReference(String localReference) async {
    final normalized = localReference.toUpperCase();
    final drafts = await all();

    return drafts
        .where((draft) => draft.localReference.toUpperCase() == normalized)
        .toList();
  }

  Future<void> removeForReference(String localReference) async {
    final normalized = localReference.toUpperCase();
    final drafts = await all();
    await _save(
      drafts
          .where((draft) => draft.localReference.toUpperCase() != normalized)
          .toList(),
    );
  }

  Future<void> _save(List<OfflineReturnDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
